#!/usr/bin/env bash

# WARNING: do not run `bashvirt.sh` directly, source it from launching script
#          under a dedicated `vmdir`

logfile=${vmdir}/journal.txt

errf() {
    [[ -n "${vmdir}" ]] && printf "${@}" >> ${logfile}
    printf "${@}" >&2; exit 1
}

print_help() {
cat << EOB
usage: $(basename $0) [actions]
actions:
    tpl                     print launching script template
    ls                      list running virtual machines
                            boot virtual machine normally without arguments
    reset                   reset virtual machine
    kill                    kill virtual machine
    lg                      start looking-glass-client
    rdp                     start sdl-freerdp3 client
    tty [1-7]               send key combo ctrl-alt-f[1-7] to virtual machine
    mac                     return MAC addresses
    ip                      return IP addresses
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

#; vmdir is required, to store all the runtime files
vmdir=\$(dirname \$(realpath \${BASH_SOURCE[0]}))

#; boot from iso
#bootiso=path/to/windows.iso

#; for non-boot iso:
#nonbootiso=path/to/virtio.iso

#; shared folder between host and guest (virtiofs)
#viofsdir=path/to

#; graphic card, [std|virtio|qxl|pci_addr], default is std
#gpu=virtio
#gpu=03:00.0

#; to enable looking glass, gpu must be a PCI address to enable this
#; looking glass type, [kvmfr|shm], shm means standard shared memory
#looking_glass_type=shm
#; looking glass shm file index for:
#; /dev/kvmfr[0,1,...], /dev/shm/looking-glass-[0,1,...]
#looking_glass_id=1

#; fullscreen mode, default is yes
#fullscreen=no

#; network cards mode, [qemu|nat|lan|natlan|none], default is qemu
#nic=nat

#; uefi boot mode [yes|no], default is yes
#uefi=no

#; cpus, default is 2
#; check physical cpu info with command \`lscpu\`, or \`cat /proc/cpuinfo\`
#cpus=4

#; memory, default is 4G
#mem=8G

#; initial disk size, default is 120G
#storage=80G

#; enable hyper-v enlightenments for windows guest, [no|yes], default is no
#hyperv=yes

#; enable tpm [no|yes], default is no
#tpm=yes

#; display mode [sdl|gtk|none], default is sdl
#display=gtk

#; resolution, default is 1920x1080
#resolution=2560x1440

#; disk image file, default is \${vmdir}/disk.qcow2, auto created if not exists
#disk=\${vmdir}/disk.qcow2

#; disk drive [virtio|sata], default is virtio
#disk_adapter=sata

#; network drive [virtio|e1000], default is virtio
#nic_adapter=e1000

#; enable if linux guest's uid/gid are not 1000 (virtiofs)
#guest_uid=1000
#guest_gid=1000

#; if you want to add additional qemu options, use:
#qemu_options_extra="..."

source \$(which bashvirt.sh) "\${@}"
EOB
}

list_running_vms() {
    local pids=$(pidof qemu-system-x86_64)
    [[ -n "${pids}" ]] || exit 0
    echo "${pids}" \
        | xargs ps --no-headers -o command -p \
        | grep -oE " -name \w+ " \
        | awk '{print $2}' \
        | xargs
}

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
esac

[[ -n "${vmdir}" ]] || errf "vmdir is undefined\n"
[[ -d "${vmdir}" ]] || errf "directory not found: ${vmdir}\n"
vmname=$(basename "${vmdir}")

command_check() {
    command -v ${1} &>/dev/null || errf "command not found: ${1}\n"
}

#################################################################################
# Disk Image
#################################################################################

storage=${storage:-120G}
disk=${disk:-${vmdir}/disk.qcow2}
[[ "${disk##*.}" == "qcow2" ]] && disk_format=qcow2 || disk_format=raw
if [[ ! -f ${disk} ]]; then
    qemu-img create -f ${disk_format} ${disk} -o nocow=on ${storage}
fi

disk_adapter=${disk_adapter:-virtio}
case "${disk_adapter}" in
    virtio)
        disk_model="virtio-blk-pci"
        ;;
    sata)
        disk_model="ide-hd"
        ;;
    *)
        errf "disk_adapter only support: <virtio|sata>\n"
        ;;
esac

disk_devices="-drive file=${disk},if=none,id=disk0,format=${disk_format}"
disk_devices+=" -device ${disk_model},drive=disk0,bootindex=1"

if [[ "${disk_adapter}" == "sata" ]]; then
    disk_devices="-device ahci,id=ahci0 ${disk_devices},bus=ahci0.0"
fi

#################################################################################
# CDROM
#################################################################################

if [[ -n "${bootiso}" ]]; then
    if [[ -f "${bootiso}" ]]; then
        bootcd="-drive file=${bootiso},media=cdrom,if=none,id=cd0"
        bootcd+=" -device ide-cd,drive=cd0,bootindex=0"
    else
       errf "file not found: ${bootiso}\n"
    fi
fi

if [[ -n "${nonbootiso}" ]]; then
    if [[ -f "${nonbootiso}" ]]; then
        nonbootcd="-drive file=${nonbootiso},media=cdrom"
    else
        errf "file not found: ${nonbootiso}\n"
    fi
fi


#################################################################################
# UEFI / BIOS
#################################################################################

# OVMF_CODE.secboot.fd
ovmf_ro=/usr/share/edk2/x64/OVMF_CODE.4m.fd
[[ -f "${ovmf_ro}" ]] || ovmf_ro=/usr/share/edk2/ovmf/OVMF_CODE.fd
ovmf_var=/usr/share/edk2/x64/OVMF_VARS.4m.fd
[[ -f "${ovmf_var}" ]] || ovmf_var=/usr/share/edk2/ovmf/OVMF_VARS.fd
ovmf_vm="${vmdir}/OVMF_VARS.fd"

uefi=${uefi:-yes}
if [[ "${uefi}" == "yes" ]]; then
    [[ -f ${ovmf_vm} ]] || cp "${ovmf_var}" "${ovmf_vm}"
    uefi_firms="-drive if=pflash,format=raw,readonly=on,file=${ovmf_ro}"
    uefi_firms+=" -drive if=pflash,format=raw,file=${ovmf_vm}"
fi

#################################################################################
# Graphic Card
#################################################################################

resolution=${resolution:-1920x1080}
resolution=$(echo "${resolution}" | tr '[:upper:]' '[:lower:]')

if [[ ! "${resolution}" =~ ^[1-9]+[0-9]+x[1-9]+[0-9]+$ ]]; then
    errf "invalid resolution ${resolution}\n"
fi

IFS=x read -ra resarr <<< "${resolution}"
resargs="xres=${resarr[0]},yres=${resarr[1]}"
vga_device="-device VGA,${resargs}"

gpu=${gpu:-std}
pciaddr_pattern=^[0-9a-f]{2}:[0-9a-f]{2}.[0-9a-f]$
if [[ "${gpu}" == "std" ]]; then
    gpu_devices="${vga_device}"
elif [[ "${gpu}" == "virtio" ]]; then
    gpu_devices="-device virtio-vga-gl,${resargs}"
elif [[ "${gpu}" == "qxl" ]]; then
    gpu_devices="-device qxl-vga,${resargs}"
elif [[ "${gpu}" =~ ${pciaddr_pattern} ]]; then
    gpu_devices="${vga_device} -device vfio-pci,host=${gpu}"
else
    errf "gpu only support: <std|virtio|qxl|pci_addr+kvmfrid>\n"
fi

looking_glass_type=${looking_glass_type:-kvmfr}
[[ "${looking_glass_type}" == "kvmfr" || "${looking_glass_type}" == "shm" ]] \
    || errf "looking_glass_type only support: <kvmfr|shm>\n"
spice_sock=${vmdir}/spice.sock
if [[ "${gpu}" =~ ${pciaddr_pattern} && "${looking_glass_id}" =~ ^[0-9]{1}$ ]]; then
    spice_devices="-spice unix=on,addr=${spice_sock},disable-ticketing=on"
    spice_devices+=" -device virtio-serial-pci -chardev spicevmc,id=spicechar,name=vdagent"
    spice_devices+=" -device virtserialport,chardev=spicechar,name=com.redhat.spice.0"
    if [[ "${looking_glass_type}" == "kvmfr" ]]; then
        lg_shm_devf=/dev/kvmfr${looking_glass_id}
    else
        lg_shm_devf=/dev/shm/looking-glass-${looking_glass_id}
    fi
    lg_mem_size=$(cat /etc/modprobe.d/kvmfr.conf | cut -d'=' -f 2 | cut -d',' -f "$((looking_glass_id+1))")
    lg_devices="-object memory-backend-file,id=looking-glass,share=on"
    lg_devices+=",mem-path=${lg_shm_devf},size=${lg_mem_size}M"
    lg_devices+=" -device ivshmem-plain,memdev=looking-glass"
    lg_devices+=" -device virtio-keyboard -device virtio-mouse"
else
    [[ "${display}" == "none" ]] || glopt=",gl=on"
fi

display=${display:-sdl}
[[ "${display}" == "sdl" || "${display}" == "gtk" || "${display}" == "none" ]] \
    || errf "display only support: <sdl|gtk|none>\n"

display_device="-display ${display}${glopt}"

fullscreen=${fullscreen:-yes}
[[ "${fullscreen}" == "yes" ]] && display_device+=",full-screen=on"

# [[ "${display}" == "gtk" ]] && display_device+=" -usb -device usb-tablet"

#################################################################################
# Network Card
#################################################################################

nic_adapter=${nic_adapter:-virtio}
case "${nic_adapter}" in
    virtio)
        nic_model="virtio-net-pci"
        ;;
    e1000)
        nic_model="e1000"
        ;;
    *)
        errf "nic_adapter only support: <virtio|e1000>\n"
        ;;
esac

gen_mac() {
    local hash=$(printf "${vmname}:${1}" | sha256sum)
    echo "52:54:${hash:0:2}:${hash:2:2}:${hash:4:2}:${hash:6:2}"
}

bridge_check() {
    local brg=${1:-brlan}
    if ! ip link show | grep -q "${brg}"; then
        errf "network bridge not found: ${brg}\n"
    fi
    if ! grep -q "allow ${brg}" /etc/qemu/bridge.conf; then
        errf "${brg} not found in /etc/qemu/bridge.conf \n"
    fi
}

case "${nic}" in
    ""|qemu)
        nic_devices="-nic user,model=${nic_model},mac=$(gen_mac user)"
        ;;
    nat)
        bridge_check brnat
        nic_devices="-nic bridge,br=brnat,model=${nic_model},mac=$(gen_mac brnat)"
        ;;
    lan)
        bridge_check brlan
        nic_devices="-nic bridge,br=brlan,model=${nic_model},mac=$(gen_mac brlan)"
        ;;
    natlan)
        bridge_check brnat
        bridge_check brlan
        nic_devices="-nic bridge,br=brnat,model=${nic_model},mac=$(gen_mac brnat)"
        nic_devices+=" -nic bridge,br=brnat,model=${nic_model},mac=$(gen_mac brlan)"
        ;;
    none)
        nic_devices=""
        ;;
    *)
        errf "nic only support: <qemu|nat|lan|natlan|none>\n"
        ;;
esac

ip_scan() {
    command_check arp-scan
    local natip
    local lanip
    if ip link | grep brnat | grep -q "state UP"; then
        natip=$(arp-scan -x -l -I brnat | grep $(gen_mac brnat) | awk '{ printf $1 }')
        [[ -n "${natip}" ]] && echo "brnat: ${natip}"
    fi
    if ip link | grep brlan | grep -q "state UP"; then
        lanip=$(arp-scan -x -l -I brlan | grep $(gen_mac brlan) | awk '{ printf $1 }')
        [[ -n "${lanip}" ]] && echo "brlan: ${lanip}"
    fi
}

#################################################################################
# CPU Model
#################################################################################

cpu_model="host"

# Enable topoext for AMD CPU
isamd=$(lscpu | grep "AuthenticAMD")
[[ -n "${isamd}" ]] && cpu_model+=",topoext=on"

# Hyper-V Enlightenment
if [[ -n "${hyperv}" && "${hyperv}" == "yes" ]]; then
    cpu_model+=",hv_relaxed,hv_vapic,hv_spinlocks=0xfff"
    cpu_model+=",hv_vpindex,hv_synic,hv_time,hv_stimer"
    cpu_model+=",hv_tlbflush,hv_tlbflush_ext,hv_ipi,hv_stimer_direct"
    cpu_model+=",hv_runtime,hv_frequencies,hv_reenlightenment"
    cpu_model+=",hv_avic,hv_xmm_input"
    cpu_model+=" -rtc base=localtime"
fi

#################################################################################
# TPM
#################################################################################

tpm_sock=${vmdir}/swtpm.sock
tpm_pidf=${tpm_sock}.pid
tpm_pid=$([[ -f ${tpm_pidf} ]] && cat ${tpm_pidf})

if [[ "${tpm}" == "yes" ]]; then
    tpm_devices="-chardev socket,id=chartpm,path=${tpm_sock}"
    tpm_devices+=" -tpmdev emulator,id=tpm0,chardev=chartpm -device tpm-tis,tpmdev=tpm0"
fi

is_pid_swtpm() {
    ps -o command= -p ${1} | grep -q swtpm
}

init_swtpm() {
    command_check swtpm
    if [[ -z "${tpm_pid}" ]] || [[ ! $(is_pid_swtpm "${tpm_pid}") ]]; then
        swtpm socket --tpm2 --tpmstate dir=${vmdir} \
            --ctrl type=unixio,path=${tpm_sock} \
            --pid file=${tpm_pidf} &
    fi
}

kill_swtpm() {
    if [[ -f ${tpm_pidf} ]]; then
        $(is_pid_swtpm $(cat ${tpm_pidf})) && kill -9 $(cat ${tpm_pidf})
    fi
}

#################################################################################
# memory, virtiofs
#################################################################################

mem=${mem:-4G}
guest_uid=${guest_uid:-1000}
guest_gid=${guest_gid:-1000}

viofs_bin=virtiofsd
viofs_exec=/usr/lib/${viofs_bin}
viofs_sock=${vmdir}/${viofs_bin}.sock
viofs_pidf=${viofs_sock}.pid
viofs_pid=$([[ -f ${viofs_pidf} ]] && cat ${viofs_pidf})

if [[ -n "${viofsdir}" && -d "${viofsdir}" && -f ${viofs_exec} ]]; then
    viofs_devices="-object memory-backend-memfd,id=mem,size=${mem},share=on"
    viofs_devices+=" -numa node,memdev=mem"
    viofs_devices+=" -chardev socket,id=viofsdev,path=${viofs_sock}"
    viofs_devices+=" -device vhost-user-fs-pci,chardev=viofsdev,tag=VirtIOFS"
fi

is_pid_viofs() {
    ps -o command= -p ${1} | grep -q ${viofs_bin}
}

init_viofs() {
    if [[ -n "${viofsdir}" ]]; then
        [[ -d "${viofsdir}" ]] || errf "dir not found: ${viofsdir}\n"
        [[ -f "${viofs_exec}" ]] || errf "command not found: ${viofs_exec}\n"
        if [[ -z "${viofs_pid}" ]] || [[ ! $(is_pid_viofs "${viofs_pid}") ]]; then
            host_uid=$(id -u)
            host_gid=$(id -g)
            ${viofs_exec} --sandbox namespace \
                --socket-path ${viofs_sock} \
                --shared-dir "${viofsdir}" \
                --translate-uid host:${host_uid}:${guest_uid}:1 \
                --translate-gid host:${host_gid}:${guest_gid}:1 \
                --translate-uid squash-guest:0:${host_uid}:4294967295 \
                --translate-gid squash-guest:0:${host_gid}:4294967295 \
                &
        fi
    fi
}

kill_viofs() {
    if [[ -f ${viofs_pidf} ]]; then
        $(is_pid_viofs $(cat ${viofs_pidf})) && kill -9 $(cat ${viofs_pidf})
    fi
}

#################################################################################
# QEMU Options builder
#################################################################################

# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
cpus=${cpus:-2}

qemu_pidf=${vmdir}/qemu.pid
monitor_sock=${vmdir}/qemu-monitor.sock

audio_devices="-device ich9-intel-hda"
audio_devices+=" -audiodev pipewire,id=snd0 -device hda-output,audiodev=snd0"

qemu_options="-enable-kvm -machine q35 -name ${vmname}"
qemu_options+=" -cpu ${cpu_model} -smp ${cpus} -m ${mem} -device qemu-xhci"
qemu_options+=" -monitor unix:${monitor_sock},server,nowait -pidfile ${qemu_pidf}"
qemu_options+=" ${uefi_firms} ${tpm_devices}"
qemu_options+=" ${disk_devices} ${nic_devices}"
qemu_options+=" ${bootcd} ${nonbootcd}"
qemu_options+=" ${gpu_devices} ${display_device} ${audio_devices}"
qemu_options+=" ${viofs_devices}"
qemu_options+=" ${spice_devices} ${lg_devices}"

#################################################################################
# QEMU start
#################################################################################

qemu_deps_prepare() {
    [[ "${tpm}" == "yes" ]] && init_swtpm
    init_viofs
    return 0
}

qemu_err_fallback() {
    [[ "${tpm}" == "yes" ]] && kill_swtpm
    kill_viofs
    return 0
}

qemu_running_check() {
    [[ -f ${qemu_pidf} ]] || return 0
    proc_comm=$(cat ${qemu_pidf} | xargs -I{} ps -o command= -p {})
    if [[ "${proc_comm}" =~ "qemu-system-x86_64" ]]; then
        errf "vm already running\n"
    fi
}

qemu_start() {
    qemu_running_check
    trap 'qemu_err_fallback; exit 1' ERR
    qemu_deps_prepare
    qemu-system-x86_64 ${qemu_options} ${qemu_options_extra} 2> >(tee -a ${logfile})
}

#################################################################################
# QEMU Monitor
#################################################################################

monitor_connect() {
    socat -,echo=0,icanon=0 unix-connect:${monitor_sock}
}

monitor_exec() {
    if [[ -S ${monitor_sock} ]]; then
        echo "${@}" | socat - UNIX-CONNECT:${monitor_sock} | tail --lines=+2 | grep -v '^(qemu)'
    fi
}

id_pattern=^[0-9a-f]{4}:[0-9a-f]{4}$

usb_attach() {
    local devid=$(echo "${1}" | tr -d [:space:])
    if [[ ! "${devid}" =~ $id_pattern ]]; then
        errf "invalid device ID\n"
    fi
    command_check lsusb
    lsusb | grep -q ${devid} || errf "device not found: ${devid}\n"
    local vendid=$(echo "${devid}" | cut -d : -f 1)
    local prodid=$(echo "${devid}" | cut -d : -f 2)
    local qexec="device_add usb-host"
    qexec+=",vendorid=0x${vendid},productid=0x${prodid}"
    qexec+=",id=usb${vendid}${prodid}"
    monitor_exec "${qexec}"
}

usb_detach() {
    local devid=$(echo "${1}" | tr -d [:space:])
    if [[ ! "${devid}" =~ $id_pattern ]]; then
        errf "invalid device ID\n"
    fi
    local vendid=$(echo "${devid}" | cut -d : -f 1)
    local prodid=$(echo "${devid}" | cut -d : -f 2)
    monitor_exec "device_del usb${vendid}${prodid}"
}

usb_list() {
    monitor_exec "info usb"
}

switch_tty() {
    if [[ ! "${1}" =~ ^[1-7]$ ]]; then
        errf "invalid tty number\n"
    fi
    monitor_exec sendkey ctrl-alt-f${1}
}

rdp_conn() {
    local ipaddr=$(ip_scan | grep brnat | cut -d' ' -f2)
    [[ -n "${ipaddr}" ]] || errf "IP address not found for brnat\n"
    sdl-freerdp3 +dynamic-resolution /v:${ipaddr} "${@}"
}

kill_qemu() {
    [[ -f ${qemu_pidf} ]] || exit 0
    cat ${qemu_pidf} | xargs kill -9
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
    kill)
        kill_qemu
        ;;
    lg)
        looking-glass-client -f ${lg_shm_devf} -c ${spice_sock} -p 0
        ;;
    rdp)
        shift
        rdp_conn "${@}"
        ;;
    tty)
        shift
        switch_tty ${@}
        ;;
    mac)
        echo "brnat: $(gen_mac brnat)"
        echo "brlan: $(gen_mac brlan)"
        ;;
    ip)
        ip_scan
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
