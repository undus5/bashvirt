#!/usr/bin/env bash

err() {
    printf "%s\n" "${1}" >&2; exit 1
}

[[ -z ${_sdir} ]] && err "_sdir is undefined, \
    set with \`_sdir=\$\(dirname \$\(realpath \$\{BASH_SOURCE[0]\}\)\)\`"

#################################################################################
# Disk Image
#################################################################################

[[ -z ${_disk} ]] && _disk=${_sdir}/disk.qcow2

qemu_disk_check() {
    if [[ ! -f ${_disk} ]]; then
        err "file not found: $(basename ${_disk}), create via command: \
            \`qemu-img create -f qcow2 $(basename ${_disk}) -o nocow=on 40G\`"
    fi
}

#################################################################################
# UEFI / BIOS
#################################################################################

[[ -z ${_bootmode} ]] && _bootmode="uefi"

if [[ "${_bootmode}" == "uefi" ]]; then
    _ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
    _ovmf_var=${_sdir}/OVMF_VARS.4m.fd
    if [[ ! -f ${_ovmf_var} ]]; then
        err "$(basename ${_ovmf_var}) not found, copy from: /usr/share/edk2/x64/"
    fi
    _uefi_drives="\
        -drive if=pflash,format=raw,readonly=on,file=${_ovmf_ro} \
        -drive if=pflash,format=raw,file=${_ovmf_var}"
fi

#################################################################################
# Graphic Card
#################################################################################

[[ -z ${_gpu} ]] && _gpu=virtio
case ${_gpu} in
    std|qxl)
        _gpu_device="-vga ${_gpu}"
        ;;
    virtio)
        _gpu_device="-device virtio-vga-gl"
        ;;
esac

#################################################################################
# BootCD
#################################################################################

if [[ -n ${_bootiso} ]]; then
    [[ -f ${_bootiso} ]] || err "file not found: ${_bootiso}"
    _bootcd="\
        -drive file=${_bootiso},media=cdrom,if=none,id=cd0 \
        -device ide-cd,drive=cd0,bootindex=0"
fi

#################################################################################
# TPM
#################################################################################

_tpm_dir=${_sdir}
_tpm_pid=${_tpm_dir}/swtpm.pid
_tpm_sock=${_tpm_dir}/swtpm.sock

if [[ "${_tpm_on}" == "yes" ]]; then
    _tpm_devices="\
        -chardev socket,id=chrtpm,path=${_tpm_sock} \
        -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
fi

is_pid_swtpm() {
    ps -o command= -p ${1} | grep -q ${_tpm_dir}
}

init_swtpm() {
    command -v swtpm &>/dev/null || err "swtpm: command not found"
    [[ -d ${_tpm_dir} ]] || err "$(basename ${_tpm_dir}): directory not found"
    if [[ ! -f ${_tpm_pid} ]] || [[ ! $(is_pid_swtpm $(cat ${_tpm_pid})) ]]; then
        swtpm socket --tpm2 \
            --tpmstate dir=${_tpm_dir} \
            --ctrl type=unixio,path=${_tpm_sock} \
            --pid file=${_tpm_pid} &
    fi
}

kill_swtpm() {
    [[ -f ${_tpm_pid} ]] && \
        $(is_pid_swtpm $(cat ${_tpm_pid})) && \
        kill -9 $(cat ${_tpm_pid})
}

#################################################################################
# QEMU Options builder
#################################################################################

[[ -z ${_mem} ]] && _mem=4G
# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
[[ -z ${_cpus} ]] && _cpus=4
_qemu_pid=${_sdir}/qemu.pid
_monitor_sock=${_sdir}/monitor.sock

gen_mac_addr() {
    printf "$(basename ${_sdir})" | sha256sum |\
        awk -v offset="$(( ${1} + 7 ))" '{ printf "52:54:%s:%s:%s:%s\n", \
        substr($1,1,2), substr($1,3,2), substr($1,5,2), substr($1,offset,2) }'
}

_qemu_options="\
    -enable-kvm -cpu host -smp ${_cpus} -m ${_mem} -machine q35 \
    -drive file=${_disk},if=none,id=disk0 \
    -device virtio-blk-pci,drive=disk0,bootindex=1 \
    -nic bridge,br=br0,model=virtio-net-pci,mac=$(gen_mac_addr 0) \
    -nic bridge,br=br1,model=virtio-net-pci,mac=$(gen_mac_addr 1) \
    -audiodev pipewire,id=snd0 -device ich9-intel-hda -device hda-duplex,audiodev=snd0 \
    -monitor unix:${_monitor_sock},server,nowait -device qemu-xhci \
    -display sdl,gl=on,full-screen=on ${_gpu_device} \
    -pidfile ${_qemu_pid} ${_uefi_drives} ${_bootcd} ${_tpm_devices}"

#################################################################################
# QEMU start
#################################################################################

qemu_prerequisite() {
    [[ "${_tpm_on}" == "yes" ]] && init_swtpm
    return 0
}

qemu_err_fallback() {
    [[ "${_tpm_on}" == "yes" ]] && kill_swtpm
    return 0
}

qemu_running_check() {
    if [[ -f ${_qemu_pid} ]]; then
        _proc_comm=$(cat ${_qemu_pid} | xargs -I{} ps -p {} -o command=)
        [[ "${_proc_comm}" =~ "qemu-system-x86_64" ]] && err "vm already running"
    fi
}

qemu_start() {
    qemu_running_check
    qemu_disk_check
    trap 'qemu_err_fallback; exit 1' ERR
    qemu_prerequisite
    qemu-system-x86_64 ${_qemu_options} ${_qemu_options_ext} 2>>${_sdir}/qemu_err.log
}

#################################################################################
# QEMU Monitor
#################################################################################

monitor_connect() {
    socat -,echo=0,icanon=0 unix-connect:${_monitor_sock}
}

monitor_invoke() {
    [[ -S ${_monitor_sock} ]] && echo "${@}" | \
        socat - UNIX-CONNECT:${_monitor_sock} | \
        tail --lines=+2 | grep -v '^(qemu)'
}

usb_attach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ ^[a-z0-9]{4}:[a-z0-9]{4}$ ]] || err "invalid device ID"
    local _vendid=$(echo "${_arg}" | cut -d : -f 1)
    local _prodid=$(echo "${_arg}" | cut -d : -f 2)
    monitor_invoke \
        "device_add usb-host,vendorid=0x${_vendid},productid=0x${_prodid},id=${_devid}"
}

usb_detach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ ^[a-z0-9]{4}:[a-z0-9]{4}$ ]] || err "invalid device ID"
    monitor_invoke "device_del ${_devid}"
}

usb_list() {
    monitor_invoke "info usb"
}

#################################################################################
# Script Options Dispatcher
#################################################################################

print_help() {
cat << EOB
usage: $(basename $0) [actions]
actions:
                            boot normally without actions
    usb-attach <device_id>  passthrough usb device to virtual machine
    usb-detach <device_id>
    usb-list                list attached devices
    invoke                  send command to qemu monitor
    conn                    connect qemu monitor
    -h, --help              help info
device_id:
    looks like "1d6b:0002", get from command \`lsusb\`, 
EOB
}

case ${1} in
    "")
        qemu_start
        ;;
    usb-attach)
        shift
        usb_attach ${1}
        ;;
    usb-detach)
        shift
        usb_detach ${1}
        ;;
    usb-list)
        usb_list
        ;;
    invoke)
        shift
        monitor_invoke ${@}
        ;;
    conn)
        monitor_connect
        ;;
    -h|--help)
        print_help
        ;;
    *)
        print_help
        ;;
esac

