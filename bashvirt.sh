#!/usr/bin/env bash

printerr() {
    printf "${@}" >&2; exit 1
}

_caller_path=$(realpath $0)
_source_path=$(realpath ${BASH_SOURCE[0]})

[[ "${_caller_path}" == "${_source_path}" ]] && \
    printerr "do not run this script directly, source it\n"

[[ -z "${_vmdir}" ]] && printerr "_vmdir is undefined\n"

#################################################################################
# Disk Image
#################################################################################

[[ -z "${_disk_file}" ]] && _disk_file=${_vmdir}/disk.qcow2
[[ -z "${_disk_drive}" ]] && _disk_drive="sata"

case "${_disk_drive}" in
    sata)
        _diskdev="ide-hd"
        ;;
    virtio)
        _diskdev="virtio-blk-pci"
        ;;
    *)
        printerr "_disk_drive only support: <sata|virtio>\n"
        ;;
esac

_disk_devices="\
    -drive file=${_disk_file},if=none,id=disk0 \
    -device ${_diskdev},drive=disk0,bootindex=1"

[[ "${_disk_drive}" == "sata" ]] && \
    _disk_devices="-device ahci,id=ahci0 ${_disk_devices},bus=ahci0.0"

qemu_disk_check() {
    if [[ ! -f ${_disk_file} ]]; then
        printf "file not found: $(basename ${_disk_file})\n"
        printerr "create via: \`qemu-img create -f qcow2 $(basename ${_disk_file}) -o nocow=on 40G\`\n"
    fi
}

#################################################################################
# BootCD
#################################################################################

if [[ -n ${_boot_iso} ]]; then
    [[ -f ${_boot_iso} ]] || printerr "file not found: ${_boot_iso}\n"
    _bootcd="\
        -drive file=${_boot_iso},media=cdrom,if=none,id=cd0 \
        -device ide-cd,drive=cd0,bootindex=0"
fi

[[ "${_disk_drive}" == "sata" ]] && \
    _bootcd="${_bootcd},bus=ahci0.1"

#################################################################################
# BIOS / UEFI
#################################################################################

[[ -z ${_boot_mode} ]] && _boot_mode="bios"

if [[ "${_boot_mode}" == "uefi" ]]; then
    _ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
    _ovmf_var=${_vmdir}/OVMF_VARS.4m.fd
    if [[ ! -f ${_ovmf_var} ]]; then
        printf "file not found: $(basename ${_ovmf_var})\n"
        printerr "copy from: /usr/share/edk2/x64/OVMF_VARS.4m.fd\n"
    fi
    _uefi_drives="\
        -drive if=pflash,format=raw,readonly=on,file=${_ovmf_ro} \
        -drive if=pflash,format=raw,file=${_ovmf_var}"
fi

#################################################################################
# TPM
#################################################################################

_tpm_pid=${_vmdir}/swtpm.pid
_tpm_sock=${_vmdir}/swtpm.sock

if [[ "${_tpm_on}" == "yes" ]]; then
    _tpm_devices="\
        -chardev socket,id=chrtpm,path=${_tpm_sock} \
        -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0"
fi

is_pid_swtpm() {
    ps -o command= -p ${1} | grep -q swtpm
}

init_swtpm() {
    command -v swtpm &>/dev/null || printerr "swtpm: command not found\n"
    if [[ ! -f ${_tpm_pid} ]] || [[ ! $(is_pid_swtpm $(cat ${_tpm_pid})) ]]; then
        swtpm socket --tpm2 \
            --tpmstate dir=${_vmdir} \
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
# Graphic Card
#################################################################################

[[ -z "${_gpu_drive}" ]] && _gpu_drive=std
case "${_gpu_drive}" in
    std|qxl)
        _gpu_device="-vga ${_gpu_drive}"
        ;;
    virtio)
        _gpu_device="-device virtio-vga-gl"
        ;;
    *)
        printerr "_gpu_drive only support: <std|qxl|virtio>\n"
        ;;
esac

#################################################################################
# Network Card
#################################################################################

[[ -z "${_nic_drive}" ]] && _nic_drive="e1000"

case "${_nic_drive}" in
    e1000)
        _nic_model="e1000"
        ;;
    virtio)
        _nic_model="virtio-net-pci"
        ;;
    *)
        printerr "_nic_drive only support: <e1000|virtio>\n"
        ;;
esac

[[ -z "${_nic_mode}" ]] && _nic_mode="user"

gen_mac_addr() {
    printf "$(basename ${_vmdir})" | sha256sum |\
        awk -v offset="$(( ${1} + 7 ))" '{ printf "52:54:%s:%s:%s:%s\n", \
        substr($1,1,2), substr($1,3,2), substr($1,5,2), substr($1,offset,2) }'
}

case "${_nic_mode}" in
    user)
        _nic_devices="-nic user,model=${_nic_model},mac=$(gen_mac_addr 0)"
        ;;
    br0br1)
        ip link show | grep br0 &>/dev/null || \
            printerr "network bridge not found: br0\n"
        ip link show | grep br1 &>/dev/null || \
            printerr "network bridge not found: br1\n"
        grep -q 'allow br0' /etc/qemu/bridge.conf || \
            printerr "br0 not found in /etc/qemu/bridge.conf \n"
        grep -q 'allow br1' /etc/qemu/bridge.conf || \
            printerr "br1 not found in /etc/qemu/bridge.conf \n"
        _nic_devices="\
            -nic bridge,br=br0,model=${_nic_model},mac=$(gen_mac_addr 0) \
            -nic bridge,br=br1,model=${_nic_model},mac=$(gen_mac_addr 1)"
        ;;
    *)
        printerr "_nic_mode only support: <user|br0br1>\n"
        ;;
esac

#################################################################################
# QEMU Options builder
#################################################################################

[[ -z ${_memory} ]] && _memory=2G
# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
[[ -z ${_cpu_cores} ]] && _cpu_cores=2
_qemu_pid=${_vmdir}/qemu.pid
_monitor_sock=${_vmdir}/monitor.sock

gen_mac_addr() {
    printf "$(basename ${_vmdir})" | sha256sum |\
        awk -v offset="$(( ${1} + 7 ))" '{ printf "52:54:%s:%s:%s:%s\n", \
        substr($1,1,2), substr($1,3,2), substr($1,5,2), substr($1,offset,2) }'
}

_qemu_options="\
    -enable-kvm -cpu host -smp ${_cpu_cores} -m ${_memory} -machine q35 \
    -audiodev pa,id=snd0 -device ich9-intel-hda -device hda-duplex,audiodev=snd0 \
    -monitor unix:${_monitor_sock},server,nowait \
    -device qemu-xhci -pidfile ${_qemu_pid} \
    -display sdl,gl=on,full-screen=on ${_gpu_device} \
    ${_uefi_drives} ${_tpm_devices} ${_disk_devices} ${_bootcd} ${_nic_devices}"

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
    [[ -f ${_qemu_pid} ]] || return 0
    _proc_comm=$(cat ${_qemu_pid} | xargs -I{} ps -o command= -p {})
    [[ "${_proc_comm}" =~ "qemu-system-x86_64" ]] && printerr "vm already running\n"
}

qemu_start() {
    qemu_running_check
    qemu_disk_check
    trap 'qemu_err_fallback; exit 1' ERR
    qemu_prerequisite
    qemu-system-x86_64 ${_qemu_options} ${_qemu_options_ext} 2>>${_vmdir}/qemu_err.log
}

#################################################################################
# QEMU Monitor
#################################################################################

monitor_connect() {
    socat -,echo=0,icanon=0 unix-connect:${_monitor_sock}
}

monitor_exec() {
    [[ -S ${_monitor_sock} ]] && echo "${@}" | \
        socat - UNIX-CONNECT:${_monitor_sock} | \
        tail --lines=+2 | grep -v '^(qemu)'
}

usb_attach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ ^[a-z0-9]{4}:[a-z0-9]{4}$ ]] || printerr "invalid device ID\n"
    local _vendid=$(echo "${_arg}" | cut -d : -f 1)
    local _prodid=$(echo "${_arg}" | cut -d : -f 2)
    monitor_exec \
        "device_add usb-host,vendorid=0x${_vendid},productid=0x${_prodid},id=${_devid}"
}

usb_detach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ ^[a-z0-9]{4}:[a-z0-9]{4}$ ]] || printerr "invalid device ID\n"
    monitor_exec "device_del ${_devid}"
}

usb_list() {
    monitor_exec "info usb"
}

#################################################################################
# Script Options Dispatcher
#################################################################################

print_help() {
cat << EOB
usage: $(basename $0) [actions]
actions:
                            boot virtual machine normally without arguments
    usb-attach <device_id>  passthrough usb device to virtual machine
    usb-detach <device_id>  detach usb device
    usb-list                list attached devices
    monitor-exec            send command to qemu monitor
    monitor-connect         connect qemu monitor
    -h, --help, help        help info
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
    monitor-exec)
        shift
        monitor_exec ${@}
        ;;
    monitor-connect)
        monitor_connect
        ;;
    -h|--help|help)
        print_help
        ;;
    *)
        print_help
        ;;
esac

