# bashvirt

A simple bash script for launching QEMU virtual machine.

Libvirt is overkill for personal use, you just need several lines of commands to
launch a dedicated virtual machine.

If you want to learn the detail of what the script actually do, read the blog post
[QEMU Install Windows 11 Guest](https://undus.net/posts/qemu-install-windows11-guest/)

## Usage

First, download this repo to you local storage, such as home directory:

```
$ cd ~
$ git clone https://github.com/undus5/bashvirt.git
```

Next, let's say you want to create a virtual machine running Windows 11.

1, create a directory for storing virtual machine related files, say `~/vms/win11`:

```
$ mkdir -p ~/vms/win11
$ cd ~/vms/win11
```

2, create disk image file for the virtual machine:

```
$ qemu-img create -f qcow2 disk.qcow2 -o nocow=on 40G
```

3, create or copy example script to the vm directory, there are comments
documentation in the script:

```
$ cp ~/bashvirt/example.sh ~/vms/win11/run.sh
```

4, assume you have already downloaded Windows 11 and VirtIO iso images to
`~/Downloads`, then edit the script with text editor:

```
#!/usr/bin/bash

_vmdir=~/vms/win11

_cpus=4
_memory=8G
_boot_mode=uefi
_tpm_on=yes
_nic_mode=user
_disk_drive=virtio
_nic_drive=virtio
_gpu_drive=std
_boot_iso=~/Downloads/win11.iso
_virtio_iso=~/Downloads/virtio.iso
_qemu_options_ext="${_qemu_options_ext} -drive file=${_virtio_iso},media=cdrom"

source ~/bashvirt/bashvirt.sh
```

5, run the script to lanuch virtual machine and install operating system:

```
$ chmod u+x ~/vms/win11/run.sh
$ ~/vms/win11/run.sh
```

if anything go wrong, it would generate a log file called `qemu_err.log`.

6, after installation finished, shutdown the virtual machine, edit the script
again, comment out the iso images part, or it would boot from iso every time:

```
...

_gpu_drive=virtio
#_boot_iso=~/Downloads/win11.iso
#_virtio_iso=~/Downloads/virtio.iso
#_qemu_options_ext="${_qemu_options_ext} -drive file=${_virtio_iso},media=cdrom"

...
```

All Done.

