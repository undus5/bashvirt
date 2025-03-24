#!/usr/bin/bash

# _vmdir is required, to store all the runtime files
# e.g. _vmdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
_vmdir=path/to/vm_runtime_dir

# disk image file, default is ${_vmdir}/disk.qcow2
# create via command `qemu-img create -f qcow2 disk.qcow2 -o nocow=on 40G`
#_disk_file=${_vmdir}/disk.qcow2

# cpu cores, default is 2
# check cpu cores with command `lscpu`, or `cat /etc/proc/cpuinfo`
#_cpu_cores=4

# memory, default is 2G
#_memory=4G

# boot mode [bios|uefi], default is bios
#_boot_mode=uefi

# enable tpm [yes|no], default is no
#_tpm_on=yes

# boot from iso
#_boot_iso=path/to/windows.iso

# add more non-boot iso:
#_secondiso=path/to/virtio.iso
#_qemu_options_ext="${_qemu_options_ext} -drive file=${_secondiso},media=cdrom"

# network cards mode, [user|br0br1], default is user
#_nic_mode=br0br1

# network drive [e1000|virtio], default is e1000
#_nic_drive=virtio

# graphic card, std or qxl or virtio, optional, default is std
#_gpu_drive=virtio

# disk drive [ide|virtio], default is ide
#_disk_drive=virtio

source path/to/bashvirt.sh

