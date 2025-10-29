#!/usr/bin/bash

# _vmdir is required, to store all the runtime files
_vmdir=$(dirname $(realpath ${BASH_SOURCE[0]}))

# boot from iso
#_bootiso=path/to/windows.iso

# for non-boot iso:
#_nonbootiso=path/to/virtio.iso

# shared folder between host and guest (virtiofs)
#_viofsdir=path/to

# graphic card, [std|virtio|qxl], default is std
#_gpu=virtio

# display mode [sdl|gtk], default is sdl
#_display=gtk

# cpus, default is 2
# check physical cpu info with command `lscpu`, or `cat /proc/cpuinfo`
#_cpus=4

# memory, default is 4G
#_mem=8G

# initial disk size, default is 120G
#_storage=80G

# network cards mode, [qemu|nat|lan|natlan|none], default is qemu
#_nic=nat

# enable hyper-v enlightenments for windows guest, [no|yes], default is no
#_hyperv=yes

# enable tpm [no|yes], default is no
#_tpm=yes

# uefi boot mode [yes|no], default is yes
#_uefi=no

# disk image file, default is ${_vmdir}/disk.qcow2, auto created if not exists
#_disk=${_vmdir}/disk.qcow2

# disk drive [virtio|sata], default is virtio
#_disk_adapter=sata

# network drive [virtio|e1000], default is virtio
#_nic_adapter=e1000

# enable if linux guest's uid/gid are not 1000 (virtiofs)
#_guest_uid=1000
#_guest_gid=1000

# if you want to add additional qemu options, use:
#_qemu_options_ext="..."

source $(which bashvirt.sh) "${@}"
