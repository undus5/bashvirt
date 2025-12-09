#!/usr/bin/env bash

_warning="warning: do not run \`$(basename ${BASH_SOURCE[0]})\` directly"
_warning+=", source it from launching script under a dedicated \`_vmdir\`"
_logfile=${_vmdir}/journal.txt
eprintf() {
    [[ -n "${_vmdir}" ]] && printf "${@}" >> ${_logfile}
    printf "${@}" >&2
    printf "\n${_warning}\n" >&2
    exit 1
}

print_help() {
cat << EOB
usage: $(basename $0) [actions]
actions:
                            boot virtual machine normally without arguments
    tpl                     print template
    ls                      list running virtual machines
    lg                      start looking-glass-client
    reset                   equals to press power reset button
    tty [1-7]               send key combo ctrl-alt-f[1-7] to virtual machine
    mac                     return MAC addresses
    monitor-exec            send command to qemu monitor
    monitor-conn            connect to qemu monitor, interactive mode
    usb-attach <device_id>  passthrough usb device to virtual machine
    usb-detach <device_id>  detach usb device
    usb-list                list attached devices
    -h, --help, help        help info
device_id:
    looks like "1d6b:0002", get from command \`lsusb\` from 'usbutils' package
EOB
}

print_template() {
cat << EOB
#!/usr/bin/bash

# _vmdir is required, to store all the runtime files
_vmdir=\$(dirname \$(realpath \${BASH_SOURCE[0]}))

# boot from iso
#_bootiso=path/to/windows.iso

# for non-boot iso:
#_nonbootiso=path/to/virtio.iso

# shared folder between host and guest (virtiofs)
#_viofsdir=path/to

# graphic card, [std|virtio|qxl|pci_addr], default is std
#_gpu=virtio
#_gpu=03:00.0

# looking glass kvmfr device index, /dev/kvmfr[0,1,...]
# _gpu must be a PCI address to enable this
#_kvmfrid=1

# fullscreen mode, default is yes
#_fullscreen=no

# network cards mode, [qemu|nat|lan|natlan|none], default is qemu
#_nic=nat

# uefi boot mode [yes|no], default is yes
#_uefi=no

# cpus, default is 2
# check physical cpu info with command \`lscpu\`, or \`cat /proc/cpuinfo\`
#_cpus=4

# memory, default is 4G
#_mem=8G

# initial disk size, default is 120G
#_storage=80G

# enable hyper-v enlightenments for windows guest, [no|yes], default is no
#_hyperv=yes

# enable tpm [no|yes], default is no
#_tpm=yes

# display mode [sdl|gtk|none], default is sdl
#_display=gtk

# resolution, default is 1920x1080
#_resolution=2560x1440

# disk image file, default is \${_vmdir}/disk.qcow2, auto created if not exists
#_disk=\${_vmdir}/disk.qcow2

# disk drive [virtio|sata], default is virtio
#_disk_adapter=sata

# network drive [virtio|e1000], default is virtio
#_nic_adapter=e1000

# enable if linux guest's uid/gid are not 1000 (virtiofs)
#_guest_uid=1000
#_guest_gid=1000

# if you want to add additional qemu options, use:
#_qemu_options_ext="..."

source \$(which bashvirt.sh) "\${@}"
EOB
}

list_running_vms() {
    pidof qemu-system-x86_64 \
        | xargs ps --no-headers -o command -p \
        | grep -oE " -name \w+ " \
        | awk '{print $2}' \
        | xargs
}

_sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))

case ${1} in
    tpl)
        print_template
        exit 0
        ;;
    ls)
        list_running_vms
        exit 0
        ;;
    -h|--help|help)
        print_help
        ;;
    -h|--help|help)
        print_help
        ;;
esac

[[ -n "${_vmdir}" ]] || eprintf "_vmdir is undefined\n"
[[ -d "${_vmdir}" ]] || eprintf "directory not found: ${_vmdir}\n"
_vmname=$(basename "${_vmdir}")

#################################################################################
# Disk Image
#################################################################################

_storage=${_storage:-120G}
_disk=${_disk:-${_vmdir}/disk.qcow2}
[[ "${_disk##*.}" == "qcow2" ]] && _disk_format=qcow2 || _disk_format=raw
if [[ ! -f ${_disk} ]]; then
    qemu-img create -f ${_disk_format} ${_disk} -o nocow=on ${_storage}
fi

_disk_adapter=${_disk_adapter:-virtio}
case "${_disk_adapter}" in
    virtio)
        _disk_model="virtio-blk-pci"
        ;;
    sata)
        _disk_model="ide-hd"
        ;;
    *)
        eprintf "_disk_adapter only support: <virtio|sata>\n"
        ;;
esac

_disk_devices="-drive file=${_disk},if=none,id=disk0,format=${_disk_format}"
_disk_devices+=" -device ${_disk_model},drive=disk0,bootindex=1"

if [[ "${_disk_adapter}" == "sata" ]]; then
    _disk_devices="-device ahci,id=ahci0 ${_disk_devices},bus=ahci0.0"
fi

#################################################################################
# CDROM
#################################################################################

if [[ -n "${_bootiso}" ]]; then
    if [[ -f "${_bootiso}" ]]; then
        _bootcd="-drive file=${_bootiso},media=cdrom,if=none,id=cd0"
        _bootcd+=" -device ide-cd,drive=cd0,bootindex=0"
    else
       eprintf "file not found: ${_bootiso}\n"
    fi
fi

if [[ -n "${_nonbootiso}" ]]; then
    if [[ -f "${_nonbootiso}" ]]; then
        _nonbootcd="-drive file=${_nonbootiso},media=cdrom"
    else
        eprintf "file not found: ${_nonbootiso}\n"
    fi
fi


#################################################################################
# UEFI / BIOS
#################################################################################

_uefi=${_uefi:-yes}
if [[ "${_uefi}" == "yes" ]]; then
    # _ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd
    _ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.4m.fd
    _ovmf_var=${_vmdir}/OVMF_VARS.4m.fd
    if [[ ! -f ${_ovmf_var} ]]; then
        cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "${_vmdir}"
    fi
    _uefi_firms="-drive if=pflash,format=raw,readonly=on,file=${_ovmf_ro}"
    _uefi_firms+=" -drive if=pflash,format=raw,file=${_ovmf_var}"
fi

#################################################################################
# Graphic Card
#################################################################################

_resolution=${_resolution:-1920x1080}
_resolution=$(echo "${_resolution}" | tr '[:upper:]' '[:lower:]')

if [[ ! "${_resolution}" =~ ^[1-9]+[0-9]+x[1-9]+[0-9]+$ ]]; then
    eprintf "invalid resolution ${_resolution}\n"
fi

IFS=x read -ra _resarr <<< "${_resolution}"
_resargs="xres=${_resarr[0]},yres=${_resarr[1]}"
_vga_device="-device VGA,${_resargs}"

_gpu=${_gpu:-std}
_pciaddr_pattern=^[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]$
if [[ "${_gpu}" == "std" ]]; then
    _gpu_devices="${_vga_device}"
elif [[ "${_gpu}" == "virtio" ]]; then
    _gpu_devices="-device virtio-vga-gl,${_resargs}"
elif [[ "${_gpu}" == "qxl" ]]; then
    _gpu_devices="-device qxl-vga,${_resargs}"
elif [[ "${_gpu}" =~ ${_pciaddr_pattern} ]]; then
    _gpu_devices="${_vga_device} -device vfio-pci,host=${_gpu}"
else
    eprintf "_gpu only support: <std|virtio|qxl|pci_addr+kvmfrid>\n"
fi

_kvmfrid_pattern=^[0-9]{1}$
_kvmfrfile=/dev/kvmfr${_kvmfrid}
_spice_sock=${_vmdir}/spice.sock
if [[ "${_kvmfrid}" =~ ${_kvmfrid_pattern} && "${_gpu}" =~ ${_pciaddr_pattern} ]]; then
    _kvmfrmem=$(cat /etc/modprobe.d/kvmfr.conf | cut -d'=' -f 2 | cut -d',' -f "$((_kvmfrid+1))")
    _spice_devices="-spice unix=on,addr=${_spice_sock},disable-ticketing=on"
    _spice_devices+=" -device virtio-serial-pci -chardev spicevmc,id=spicechar,name=vdagent"
    _spice_devices+=" -device virtserialport,chardev=spicechar,name=com.redhat.spice.0"
    _kvmfr_devices="-object memory-backend-file,id=looking-glass"
    _kvmfr_devices+=",mem-path=${_kvmfrfile},size=${_kvmfrmem}M,share=yes"
    _kvmfr_devices+=" -device ivshmem-plain,id=shmem0,memdev=looking-glass"
    _kvmfr_devices+=" -device virtio-keyboard -device virtio-mouse"
else
    _glopt=",gl=on"
fi

_display=${_display:-sdl}
[[ "${_display}" == "sdl" || "${_display}" == "gtk" || "${_display}" == "none" ]] \
    || eprintf "_display only support: <sdl|gtk|none>\n"

_display_device="-display ${_display}${_glopt}"

_fullscreen=${_fullscreen:-yes}
[[ "${_fullscreen}" == "yes" ]] && _display_device+=",full-screen=on"

# [[ "${_display}" == "gtk" ]] && _display_device+=" -usb -device usb-tablet"

[[ "${_display}" == "none" ]] && _display_device=""

#################################################################################
# Network Card
#################################################################################

_nic_adapter=${_nic_adapter:-virtio}
case "${_nic_adapter}" in
    virtio)
        _nic_model="virtio-net-pci"
        ;;
    e1000)
        _nic_model="e1000"
        ;;
    *)
        eprintf "_nic_adapter only support: <virtio|e1000>\n"
        ;;
esac

gen_mac_addr() {
    local _hash=$(printf "${_vmname}:${1}" | sha256sum)
    echo "52:54:${_hash:0:2}:${_hash:2:2}:${_hash:4:2}:${_hash:6:2}"
}

bridge_check() {
    local _br=${1:-brlan}
    if ! ip link show | grep -q "${_br}"; then
        eprintf "network bridge not found: ${_br}\n"
    fi
    if ! grep -q "allow ${_br}" /etc/qemu/bridge.conf; then
        eprintf "${_br} not found in /etc/qemu/bridge.conf \n"
    fi
}

case "${_nic}" in
    ""|qemu)
        _nic_devices="-nic user,model=${_nic_model},mac=$(gen_mac_addr user)"
        ;;
    nat)
        bridge_check brnat
        _nic_devices="-nic bridge,br=brnat,model=${_nic_model},mac=$(gen_mac_addr brnat)"
        ;;
    lan)
        bridge_check brlan
        _nic_devices="-nic bridge,br=brlan,model=${_nic_model},mac=$(gen_mac_addr brlan)"
        ;;
    natlan)
        bridge_check brnat
        bridge_check brlan
        _nic_devices="-nic bridge,br=brnat,model=${_nic_model},mac=$(gen_mac_addr brnat)"
        _nic_devices+=" -nic bridge,br=brnat,model=${_nic_model},mac=$(gen_mac_addr brlan)"
        ;;
    none)
        _nic_devices=""
        ;;
    *)
        eprintf "_nic only support: <qemu|nat|lan|natlan|none>\n"
        ;;
esac

#################################################################################
# CPU Model
#################################################################################

_cpu_model="host"

# Enable topoext for AMD CPU
_isamd=$(lscpu | grep "AuthenticAMD")
[[ -n "${_isamd}" ]] && _cpu_model+=",topoext=on"

# Hyper-V Enlightenment
if [[ -n "${_hyperv}" && "${_hyperv}" == "yes" ]]; then
    _cpu_model+=",hv_relaxed,hv_vapic,hv_spinlocks=0xfff"
    _cpu_model+=",hv_vpindex,hv_synic,hv_time,hv_stimer"
    _cpu_model+=",hv_tlbflush,hv_tlbflush_ext,hv_ipi,hv_stimer_direct"
    _cpu_model+=",hv_runtime,hv_frequencies,hv_reenlightenment"
    _cpu_model+=",hv_avic,hv_xmm_input"
    _cpu_model+=" -rtc base=localtime"
fi

#################################################################################
# TPM
#################################################################################

_tpm_sock=${_vmdir}/swtpm.sock
_tpm_pidf=${_tpm_sock}.pid
_tpm_pid=$([[ -f ${_tpm_pidf} ]] && cat ${_tpm_pidf})

if [[ "${_tpm}" == "yes" ]]; then
    _tpm_devices="-chardev socket,id=chartpm,path=${_tpm_sock}"
    _tpm_devices+=" -tpmdev emulator,id=tpm0,chardev=chartpm -device tpm-tis,tpmdev=tpm0"
fi

is_pid_swtpm() {
    ps -o command= -p ${1} | grep -q swtpm
}

init_swtpm() {
    command -v swtpm &>/dev/null || eprintf "swtpm: command not found\n"
    if [[ -z "${_tpm_pid}" ]] || [[ ! $(is_pid_swtpm "${_tpm_pid}") ]]; then
        swtpm socket --tpm2 --tpmstate dir=${_vmdir} \
            --ctrl type=unixio,path=${_tpm_sock} \
            --pid file=${_tpm_pidf} &
    fi
}

kill_swtpm() {
    if [[ -f ${_tpm_pidf} ]]; then
        $(is_pid_swtpm $(cat ${_tpm_pidf})) && kill -9 $(cat ${_tpm_pidf})
    fi
}

#################################################################################
# memory, virtiofs
#################################################################################

_mem=${_mem:-4G}
_guest_uid=${_guest_uid:-1000}
_guest_gid=${_guest_gid:-1000}

_viofs_bin=virtiofsd
_viofs_exec=/usr/lib/${_viofs_bin}
_viofs_sock=${_vmdir}/${_viofs_bin}.sock
_viofs_pidf=${_viofs_sock}.pid
_viofs_pid=$([[ -f ${_viofs_pidf} ]] && cat ${_viofs_pidf})


if [[ -n "${_viofsdir}" && -d "${_viofsdir}" && -f ${_viofs_exec} ]]; then
    _viofs_devices="-object memory-backend-memfd,id=mem,size=${_mem},share=on"
    _viofs_devices+=" -numa node,memdev=mem"
    _viofs_devices+=" -chardev socket,id=viofsdev,path=${_viofs_sock}"
    _viofs_devices+=" -device vhost-user-fs-pci,chardev=viofsdev,tag=virtiofs"
fi

is_pid_viofs() {
    ps -o command= -p ${1} | grep -q ${_viofs_bin}
}

init_viofs() {
    if [[ -n "${_viofsdir}" ]]; then
        [[ -d "${_viofsdir}" ]] || eprintf "dir not found: ${_viofsdir}\n"
        [[ -f "${_viofs_exec}" ]] || eprintf "command not found: ${_viofs_exec}\n"
        if [[ -z "${_viofs_pid}" ]] || [[ ! $(is_pid_viofs "${_viofs_pid}") ]]; then
            _host_uid=$(id -u)
            _host_gid=$(id -g)
            ${_viofs_exec} --sandbox namespace \
                --socket-path ${_viofs_sock} \
                --shared-dir "${_viofsdir}" \
                --translate-uid host:${_host_uid}:${_guest_uid}:1 \
                --translate-gid host:${_host_gid}:${_guest_gid}:1 \
                --translate-uid squash-guest:0:${_host_uid}:4294967295 \
                --translate-gid squash-guest:0:${_host_gid}:4294967295 \
                &
        fi
    fi
}

kill_viofs() {
    if [[ -f ${_viofs_pidf} ]]; then
        $(is_pid_viofs $(cat ${_viofs_pidf})) && kill -9 $(cat ${_viofs_pidf})
    fi
}

#################################################################################
# QEMU Options builder
#################################################################################

# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
_cpus=${_cpus:-2}

_qemu_pidf=${_vmdir}/qemu.pid
_monitor_sock=${_vmdir}/qemu-monitor.sock

_audio_devices="-device ich9-intel-hda"
_audio_devices+=" -audiodev pipewire,id=snd0 -device hda-output,audiodev=snd0"

_qemu_options="-enable-kvm -machine q35 -name ${_vmname}"
_qemu_options+=" -cpu ${_cpu_model} -smp ${_cpus} -m ${_mem} -device qemu-xhci"
_qemu_options+=" -monitor unix:${_monitor_sock},server,nowait -pidfile ${_qemu_pidf}"
_qemu_options+=" ${_uefi_firms} ${_tpm_devices}"
_qemu_options+=" ${_disk_devices} ${_nic_devices}"
_qemu_options+=" ${_bootcd} ${_nonbootcd}"
_qemu_options+=" ${_gpu_devices} ${_display_device} ${_audio_devices}"
_qemu_options+=" ${_viofs_devices}"
_qemu_options+=" ${_spice_devices} ${_kvmfr_devices}"

#################################################################################
# QEMU start
#################################################################################

qemu_deps_prepare() {
    [[ "${_tpm}" == "yes" ]] && init_swtpm
    init_viofs
    return 0
}

qemu_err_fallback() {
    [[ "${_tpm}" == "yes" ]] && kill_swtpm
    kill_viofs
    return 0
}

qemu_running_check() {
    [[ -f ${_qemu_pidf} ]] || return 0
    _proc_comm=$(cat ${_qemu_pidf} | xargs -I{} ps -o command= -p {})
    if [[ "${_proc_comm}" =~ "qemu-system-x86_64" ]]; then
        eprintf "vm already running\n"
    fi
}

qemu_start() {
    qemu_running_check
    trap 'qemu_err_fallback; exit 1' ERR
    qemu_deps_prepare
    qemu-system-x86_64 ${_qemu_options} ${_qemu_options_ext} 2> >(tee -a ${_logfile})
}

#################################################################################
# QEMU Monitor
#################################################################################

monitor_connect() {
    socat -,echo=0,icanon=0 unix-connect:${_monitor_sock}
}

monitor_exec() {
    local _result
    if [[ -S ${_monitor_sock} ]]; then
        echo "${@}" | socat - UNIX-CONNECT:${_monitor_sock} | tail --lines=+2 | grep -v '^(qemu)'
    fi
}

_id_pattern=^[0-9a-f]{4}:[0-9a-f]{4}$

usb_attach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    if [[ ! "${_devid}" =~ $_id_pattern ]]; then
        eprintf "invalid device ID\n"
    fi
    local _vendid=$(echo "${_devid}" | cut -d : -f 1)
    local _prodid=$(echo "${_devid}" | cut -d : -f 2)
    local _qexec="device_add usb-host"
    _qexec+=",vendorid=0x${_vendid},productid=0x${_prodid}"
    _qexec+=",id=usb${_vendid}${_prodid}"
    monitor_exec "${_qexec}"
}

usb_detach() {
    local _devid=$(echo "${1}" | tr -d [:space:])
    if [[ ! "${_devid}" =~ $_id_pattern ]]; then
        eprintf "invalid device ID\n"
    fi
    local _vendid=$(echo "${_devid}" | cut -d : -f 1)
    local _prodid=$(echo "${_devid}" | cut -d : -f 2)
    monitor_exec "device_del usb${_vendid}${_prodid}"
}

usb_list() {
    monitor_exec "info usb"
}

switch_tty() {
    if [[ ! "${1}" =~ ^[1-7]$ ]]; then
        eprintf "invalid tty number\n"
    fi
    monitor_exec sendkey ctrl-alt-f${1}
}

rdp_conn() {
    [[ -f ${_vmdir}/ipaddr.sh ]] || eprintf "ipaddr.sh not found\n"
    source ${_vmdir}/ipaddr.sh
    sdl-freerdp3 +dynamic-resolution /v:${_ipaddr}
}

#################################################################################
# Options Dispatcher
#################################################################################

case ${1} in
    "")
        qemu_start
        ;;
    reset)
        monitor_exec system_reset
        ;;
    tty)
        shift
        switch_tty ${@}
        ;;
    lg)
        looking-glass-client -f ${_kvmfrfile} -c ${_spice_sock} -p 0
        ;;
    rdp)
        rdp_conn
        ;;
    mac)
        echo "brnat: $(gen_mac_addr brnat)"
        echo "brlan: $(gen_mac_addr brlan)"
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
    monitor-conn)
        monitor_connect
        ;;
    *)
        print_help
        ;;
esac
