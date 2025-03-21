#!/usr/bin/bash

_sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))

_mem=4G
# check CPU cores with `lscpu` command, or `cat /etc/proc/cpuinfo`
_cpus=4
#_bootmode=[bios|uefi], default is uefi
_bootmode=uefi
#_gpu=[std|qxl|virtio], default is virtio
_gpu=virtio
#_disk=${_sdir}/disk.qcow2

# _bootiso=path/to/windows.iso
# _secondiso=path/to/virtio.iso
# [[ -f ${_secondiso} ]] || err "file not found: ${_secondiso}"
# _qemu_options_ext="${_qemu_options_ext} -drive file=${_secondiso},media=cdrom"

source ${_sdir}/bashvirt.sh

