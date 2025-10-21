# bashvirt

A simple bash script for launching QEMU virtual machine.

Libvirt is overkill for personal use, you just need several lines of commands to
launch a dedicated virtual machine.

If you want to learn the detail of what the script actually do, read the blog post
[QEMU Install Windows 11 Guest](https://undus.net/posts/qemu-install-windows11-guest/)

## Usage

First, download this repo to you local storage, add it to `$PATH`:

```
$ cd ~
$ git clone https://github.com/undus5/bashvirt.git
$ echo 'PATH=${PATH}:~/bashvirt' >> ~/.bashrc && source ~/.bashrc
```

Next, let's say you want to create a virtual machine running Windows 11.

1, create a directory for storing virtual machine related files, say `~/vms/win11`:

```
$ mkdir -p ~/vms/win11
$ cd ~/vms/win11
```

2, create disk image file for the virtual machine:

```
$ qemu-img create -f qcow2 disk.qcow2 -o nocow=on 120G
```

3, copy template script to the vm directory as launching script,
there are detailed comments for all options:

```
$ cp ~/bashvirt/template.sh ~/vms/win11/run.sh

or

$ bashvirt.sh tpl > ~/vms/win11/run.sh
```

4, assume you have already downloaded Windows 11 and VirtIO iso images to
`~/Downloads`, then edit the script with text editor:

```
#!/usr/bin/bash

_vmdir=~/vms/win11

_cpus=4
_mem=8G
_boot_mode=uefi
_hyperv=yes
_tpm_on=yes
_gpu_drive=std
_nic_mode=qemu
_disk_drive=virtio
_nic_drive=virtio
_boot_iso=~/Downloads/win11.iso
_nonboot_iso=~/Downloads/virtio.iso

source ~/bashvirt/bashvirt.sh
```

5, run the script to lanuch virtual machine and install operating system:

```
$ chmod u+x ~/vms/win11/run.sh
$ ~/vms/win11/run.sh
```

if anything go wrong, it would generate a log file called `journal.txt`.

6, after installation finished, shutdown the virtual machine, edit the script
again, comment out the iso images part, or it would boot from iso every time:

```
...

#_boot_iso=~/Downloads/win11.iso
#_nonboot_iso=~/Downloads/virtio.iso
_gpu_drive=virtio

...
```

All Done.

## Options

Run `bashvirt.sh -h` to get help info.

```
usage: bashvirt.sh [actions]
actions:
                            boot virtual machine normally without arguments
    usb-attach <device_id>  passthrough usb device to virtual machine
    usb-detach <device_id>  detach usb device
    usb-list                list attached devices
    monitor-exec            send command to qemu monitor
    monitor-connect         connect qemu monitor
    -h, --help, help        help info
    tpl                     print template
device_id:
    looks like "1d6b:0002", get from command `lsusb`
```

