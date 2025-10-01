#!/usr/bin/bash

# _vmdir is required, to store all the runtime files
_vmdir=$(dirname $(realpath ${BASH_SOURCE[0]}))

# boot from iso
#_boot_iso=path/to/windows.iso

# add more non-boot iso:
#_second_iso=path/to/virtio.iso
#_qemu_options_ext+=" -drive file=${_second_iso},media=cdrom"

# shared folder between host and guest (virtiofs)
#_shared_dir=path/to

# enable if linux guest's uid/gid are not 1000 (virtiofs)
#_guest_uid=1000
#_guest_gid=1000

# cpus, default is 2
# check physical cpu info with command `lscpu`, or `cat /proc/cpuinfo`
#_cpus=4

# memory, default is 2G
#_memory=4G

# boot mode [bios|uefi], default is bios
#_boot_mode=uefi

# enable hyper-v enlightenments for windows guest
#_hyperv=yes

# disk drive [sata|virtio], default is sata
#_disk_drive=virtio

# graphic card, std or qxl or virtio, optional, default is std
#_gpu_drive=virtio

# network drive [e1000|virtio], default is e1000
#_nic_drive=virtio

# network cards mode, [user|brlan|brnat], default is user
#_nic_mode=brlan

# disk image file, default is ${_vmdir}/disk.qcow2
# create via command `qemu-img create -f qcow2 disk.qcow2 -o nocow=on 128G`
#_disk_image=${_vmdir}/disk.qcow2

# enable tpm [yes|no], default is no
#_tpm_on=yes

# display mode [sdl|gtk], default is sdl
#_display=gtk

source $(which bashvirt.sh) "${@}"
