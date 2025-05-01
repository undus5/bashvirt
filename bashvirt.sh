#!/usr/bin/env bash

[[ -z "${_vmdir}" ]] && printf "_vmdir is undefined\n" >&2
[[ -d "${_vmdir}" ]] || printf "dir not found: ${_vmdir}\n" >&2
_vmname=$(basename "${_vmdir}")

printerr() {
    printf "${@}" | tee -a ${_vmdir}/qemu_err.log >&2 && exit 1
}

_caller_path=$(realpath $0)
_source_path=$(realpath ${BASH_SOURCE[0]})

[[ "${_caller_path}" == "${_source_path}" ]] && \
    printerr "do not run this script directly, source it\n"

#################################################################################
# Disk Image
#################################################################################

[[ -z "${_disk_image}" ]] && _disk_image=${_vmdir}/disk.qcow2
[[ "${_disk_image##*.}" == "qcow2" ]] && _disk_format=qcow2 || _disk_format=raw
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
    -drive file=${_disk_image},if=none,id=disk0,format=${_disk_format} \
    -device ${_diskdev},drive=disk0,bootindex=1"

[[ "${_disk_drive}" == "sata" ]] && \
    _disk_devices="-device ahci,id=ahci0 ${_disk_devices},bus=ahci0.0"

qemu_disk_check() {
    if [[ ! -f ${_disk_image} && ! -b ${_disk_image} ]]; then
        local _info="file not found: ${_disk_image}\n"
        _info="${_info}how to create: \`qemu-img create -f qcow2 ${_disk_image} -o nocow=on 40G\`\n"
        printerr "${_info}"
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


#################################################################################
# BIOS / UEFI
#################################################################################

[[ -z ${_boot_mode} ]] && _boot_mode="bios"

if [[ "${_boot_mode}" == "uefi" ]]; then
    _ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
    _ovmf_var=${_vmdir}/OVMF_VARS.4m.fd
    [[ -f ${_ovmf_var} ]] || cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "${_vmdir}"
    _uefi_drives="\
        -drive if=pflash,format=raw,readonly=on,file=${_ovmf_ro} \
        -drive if=pflash,format=raw,file=${_ovmf_var}"
fi

#################################################################################
# Graphic Card
#################################################################################

[[ -z "${_gpu_drive}" ]] && _gpu_drive=std
case "${_gpu_drive}" in
    std)
        # _gpu_device="-vga ${_gpu_drive}"
        _gpu_device="-device VGA,xres=1920,yres=1080"
        ;;
    qxl)
        _gpu_device="-device qxl-vga,xres=1920,yres=1080"
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

gen_mac_addr() {
    printf "${_vmname}" | sha256sum |\
        awk -v offset="$(( ${1} + 7 ))" '{ printf "52:54:%s:%s:%s:%s\n", \
        substr($1,1,2), substr($1,3,2), substr($1,5,2), substr($1,offset,2) }'
}

[[ -z "${_nic_mode}" ]] && _nic_mode="user"

case "${_nic_mode}" in
    none|"")
        _nic_devices=""
        ;;
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
# Hyper-V Enlightenment
#################################################################################

_cpu_model="host"
if [[ -n "${_hyperv}" && "${_hyperv}" == "yes" ]]; then
    _cpu_model="${_cpu_model},hv_relaxed,hv_vapic,hv_spinlocks=0xfff"
    _cpu_model="${_cpu_model},hv_vpindex,hv_synic,hv_time,hv_stimer"
    _cpu_model="${_cpu_model},hv_tlbflush,hv_tlbflush_ext,hv_ipi,hv_stimer_direct"
    _cpu_model="${_cpu_model},hv_runtime,hv_frequencies,hv_reenlightenment"
    _cpu_model="${_cpu_model},hv_avic,hv_xmm_input"
fi

#################################################################################
# TPM
#################################################################################

_tpm_sock=${_vmdir}/swtpm.sock
_tpm_pidf=${_tpm_sock}.pid
_tpm_pid=$([[ -f ${_tpm_pidf} ]] && cat ${_tpm_pidf})

if [[ "${_tpm_on}" == "yes" ]]; then
    _tpm_devices="\
        -chardev socket,id=chartpm,path=${_tpm_sock} \
        -tpmdev emulator,id=tpm0,chardev=chartpm -device tpm-tis,tpmdev=tpm0"
fi

is_pid_swtpm() {
    ps -o command= -p ${1} | grep -q swtpm
}

init_swtpm() {
    command -v swtpm &>/dev/null || printerr "swtpm: command not found\n"
    if [[ -z "${_tpm_pid}" ]] || [[ ! $(is_pid_swtpm "${_tpm_pid}") ]]; then
        swtpm socket --tpm2 \
            --tpmstate dir=${_vmdir} \
            --ctrl type=unixio,path=${_tpm_sock} \
            --pid file=${_tpm_pidf} &
    fi
}

kill_swtpm() {
    [[ -f ${_tpm_pidf} ]] && \
        $(is_pid_swtpm $(cat ${_tpm_pidf})) && \
        kill -9 $(cat ${_tpm_pidf})
}

#################################################################################
# memory, virtiofsd
#################################################################################

[[ -z "${_memory}" ]] && _memory=2G
[[ -z "${_guest_uid}" ]] && _guest_uid=1000
[[ -z "${_guest_gid}" ]] && _guest_gid=1000

_virtiofsd_exec=/usr/lib/virtiofsd
_virtiofsd_sock=${_vmdir}/virtiofsd.sock
_virtiofsd_pidf=${_virtiofsd_sock}.pid
_virtiofsd_pid=$([[ -f ${_virtiofsd_pidf} ]] && cat ${_virtiofsd_pidf})


[[ -n "${_shared_dir}" && -d "${_shared_dir}" && -f ${_virtiofsd_exec} ]] && \
    _virtiofsd_devices="\
        -object memory-backend-memfd,id=mem,size=${_memory},share=on \
        -numa node,memdev=mem \
        -chardev socket,id=charvirtiofs,path=${_virtiofsd_sock} \
        -device vhost-user-fs-pci,chardev=charvirtiofs,tag=virtiofs"

is_pid_virtiofsd() {
    ps -o command= -p ${1} | grep -q virtiofsd
}

init_virtiofsd() {
    if [[ -n "${_shared_dir}" ]]; then
        [[ -d "${_shared_dir}" ]] || printerr "dir not found: ${_shared_dir}\n"
        [[ -f "${_virtiofsd_exec}" ]] || printerr "command not found: ${_virtiofsd_exec}\n"
        if [[ -z "${_virtiofsd_pid}" ]] || [[ ! $(is_pid_virtiofsd "${_virtiofsd_pid}") ]]; then
            _host_uid=$(id -u)
            _host_gid=$(id -g)
            ${_virtiofsd_exec} \
            --socket-path ${_virtiofsd_sock} \
            --shared-dir "${_shared_dir}" \
            --sandbox namespace \
            --translate-uid host:${_host_uid}:${_guest_uid}:1 \
            --translate-gid host:${_host_gid}:${_guest_gid}:1 \
            --translate-uid squash-guest:0:${_host_uid}:4294967295 \
            --translate-gid squash-guest:0:${_host_gid}:4294967295 \
            &
        fi
    fi
}

kill_virtiofsd() {
    [[ -f ${_virtiofsd_pidf} ]] && \
        $(is_pid_virtiofsd $(cat ${_virtiofsd_pidf})) && \
        kill -9 $(cat ${_virtiofsd_pidf})
}

#################################################################################
# QEMU Options builder
#################################################################################

# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
[[ -z "${_cpus}" ]] && _cpus=2

_qemu_pidf=${_vmdir}/qemu.pid
_monitor_sock=${_vmdir}/monitor.sock

_qemu_options="\
    -enable-kvm -machine q35 -cpu ${_cpu_model} -smp ${_cpus} \
    -m ${_memory} ${_virtiofsd_devices} \
    -audiodev pa,id=snd0 -device ich9-intel-hda -device hda-duplex,audiodev=snd0 \
    -monitor unix:${_monitor_sock},server,nowait \
    -device qemu-xhci -pidfile ${_qemu_pidf} \
    -display sdl,gl=on,full-screen=on ${_gpu_device} \
    ${_uefi_drives} ${_tpm_devices} ${_disk_devices} ${_bootcd} ${_nic_devices}"

#################################################################################
# QEMU start
#################################################################################

qemu_deps_prepare() {
    [[ "${_tpm_on}" == "yes" ]] && init_swtpm
    init_virtiofsd
    return 0
}

qemu_err_fallback() {
    [[ "${_tpm_on}" == "yes" ]] && kill_swtpm
    kill_virtiofsd
    return 0
}

qemu_running_check() {
    [[ -f ${_qemu_pidf} ]] || return 0
    _proc_comm=$(cat ${_qemu_pidf} | xargs -I{} ps -o command= -p {})
    [[ "${_proc_comm}" =~ "qemu-system-x86_64" ]] && printerr "vm already running\n"
}

qemu_start() {
    qemu_running_check
    qemu_disk_check
    trap 'qemu_err_fallback; exit 1' ERR
    qemu_deps_prepare
    qemu-system-x86_64 ${_qemu_options} ${_qemu_options_ext} 2> >(tee -a ${_vmdir}/qemu_err.log)
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
# Options Dispatcher
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

