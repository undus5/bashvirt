#!/usr/bin/env bash

# do not run this script directly, source it from template under a dedicated _vmdir

eprintf() {
    [[ -n "${_vmdir}" ]] && printf "${@}" >> ${_vmdir}/qemu_err.log
    printf "${@}" >&2
    exit 1
}

[[ -n "${_vmdir}" ]] || eprintf "_vmdir is undefined\n"
[[ -d "${_vmdir}" ]] || eprintf "directory not found: ${_vmdir}\n"
_vmname=$(basename "${_vmdir}")

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
        eprintf "_disk_drive only support: <sata|virtio>\n"
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
        eprintf "${_info}"
    fi
}

#################################################################################
# BootCD
#################################################################################

if [[ -n ${_boot_iso} ]]; then
    [[ -f ${_boot_iso} ]] || eprintf "file not found: ${_boot_iso}\n"
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
    # _usb_controller="-device qemu-xhci"
    _usb_controller="-usb"
else
    # _usb_controller="-device usb-ehci"
    _usb_controller="-usb"
fi

# [[ -z "${_tablet}" ]] && _tablet=yes
# [[ "${_tablet}" == "yes" ]] && _tablet_devices="-device usb-tablet"
[[ -z "${_display}" ]] && _display=sdl
[[ "${_display}" != "sdl" ]] && _display=gtk
[[ "${_display}" == "gtk" ]] && _tablet_devices="-device usb-tablet"

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
        eprintf "_gpu_drive only support: <std|qxl|virtio>\n"
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
        eprintf "_nic_drive only support: <e1000|virtio>\n"
        ;;
esac

gen_mac_addr() {
    printf "${_vmname}${1}" | sha256sum |\
        awk '{ printf "52:54:%s:%s:%s:%s\n", \
        substr($0,1,2), substr($0,3,2), substr($0,5,2), substr($0,7,2) }'
}

[[ -z "${_nic_mode}" ]] && _nic_mode="user"

bridge_check() {
    local _br=${1}
    [[ -z "${_br}" ]] && _br=brlan
    ip link show | grep ${_br} &>/dev/null || \
        eprintf "network bridge not found: ${_br}\n"
    grep -q "allow ${_br}" /etc/qemu/bridge.conf || \
        eprintf "${_br} not found in /etc/qemu/bridge.conf \n"
}

case "${_nic_mode}" in
    none|"")
        _nic_devices=""
        ;;
    user)
        _nic_devices="-nic user,model=${_nic_model},mac=$(gen_mac_addr user)"
        ;;
    brlan)
        bridge_check brlan
        _nic_devices="\
            -nic bridge,br=brlan,model=${_nic_model},mac=$(gen_mac_addr brlan)"
        ;;
    brnat)
        bridge_check brnat
        _nic_devices="\
            -nic bridge,br=brnat,model=${_nic_model},mac=$(gen_mac_addr brnat)"
        ;;
    *)
        eprintf "_nic_mode only support: <user|brlan|brnat>\n"
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
    command -v swtpm &>/dev/null || eprintf "swtpm: command not found\n"
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
        [[ -d "${_shared_dir}" ]] || eprintf "dir not found: ${_shared_dir}\n"
        [[ -f "${_virtiofsd_exec}" ]] || eprintf "command not found: ${_virtiofsd_exec}\n"
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
    -audiodev pipewire,id=snd0 -device ich9-intel-hda -device hda-output,audiodev=snd0 \
    -monitor unix:${_monitor_sock},server,nowait \
    -display ${_display},gl=on,full-screen=on ${_gpu_device} ${_tablet_devices} \
    -pidfile ${_qemu_pidf} \
    ${_usb_controller} \
    ${_uefi_drives} ${_tpm_devices} \
    ${_disk_devices} ${_bootcd} ${_nic_devices}"

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
    [[ "${_proc_comm}" =~ "qemu-system-x86_64" ]] && eprintf "vm already running\n"
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

_id_pattern=^[0-9a-f]{4}:[0-9a-f]{4}$

usb_attach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ $_id_pattern ]] || eprintf "invalid device ID\n"
    local _vendid=$(echo "${_devid}" | cut -d : -f 1)
    local _prodid=$(echo "${_devid}" | cut -d : -f 2)
    monitor_exec \
        "device_add usb-host,vendorid=0x${_vendid},productid=0x${_prodid},id=usb${_vendid}${_prodid}"
}

usb_detach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    [[ "${_devid}" =~ $_id_pattern ]] || eprintf "invalid device ID\n"
    local _vendid=$(echo "${_devid}" | cut -d : -f 1)
    local _prodid=$(echo "${_devid}" | cut -d : -f 2)
    monitor_exec "device_del usb${_vendid}${_prodid}"
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
    looks like "1d6b:0002", get from command \`lsusb\`
EOB
}

case ${1} in
    "")
        qemu_start
        ;;
    usb-attach)
        shift
        usb_attach ${@}
        ;;
    usb-detach)
        shift
        usb_detach ${@}
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

