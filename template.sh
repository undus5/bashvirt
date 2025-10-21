#!/usr/bin/bash

# _vmdir is required, to store all the runtime files
_vmdir=$(dirname $(realpath ${BASH_SOURCE[0]}))

# boot from iso
#_boot_iso=path/to/windows.iso

# for non-boot iso:
#_nonboot_iso=path/to/virtio.iso

# shared folder between host and guest (virtiofs)
#_shared_dir=path/to

# network cards mode, [qemu|nat|lan|natlan|none], default is qemu
#_nic_mode=nat

# graphic card, [std|virtio|qxl], default is std
#_gpu_drive=virtio

# display mode [sdl|gtk], default is sdl
#_display=gtk

# cpus, default is 2
# check physical cpu info with command `lscpu`, or `cat /proc/cpuinfo`
#_cpus=4

# memory, default is 2G
#_mem=4G

# boot mode [bios|uefi], default is uefi
#_boot_mode=bios

# enable hyper-v enlightenments for windows guest, [no|yes], default is no
#_hyperv=yes

# enable tpm2 [no|yes], default is no
#_tpm_on=yes

# disk image file, default is ${_vmdir}/disk.qcow2
# create via command `qemu-img create -f qcow2 disk.qcow2 -o nocow=on 120G`
#_disk_image=${_vmdir}/disk.qcow2

# disk drive [virtio|sata], default is virtio
#_disk_drive=sata

# network drive [virtio|e1000], default is virtio
#_nic_drive=e1000

# enable if linux guest's uid/gid are not 1000 (virtiofs)
#_guest_uid=1000
#_guest_gid=1000

# if you want to add additional qemu options, use:
#_qemu_options_ext="..."

source $(which bashvirt.sh) "${@}"
