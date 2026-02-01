# bashvirt

A bash script for launching QEMU virtual machine, optimized for personal use.

## Features

- Bridged network, host-only network
- File sharing with host (virtiofsd)
- GPU passthrough, looking glass support

If you want to learn the detail of what the script actually do, read the blog post
[QEMU/KVM Windows 11 Guest](https://undus.net/posts/qemu-kvm-win11-guest/)

## Usage

First, download this repo to you local storage, say in `/data`:

```
(user)$ cd /data
(user)$ git clone https://github.com/undus5/bashvirt.git
```

Next, let's say you want to create a virtual machine running Windows 11.

Create a directory for storing virtual machine related files, say `/data/vms/win11`:

```
(user)$ mkdir -p /data/vms/win11
(user)$ cd /data/vms/win11
```

Generate launching script from template into the the vm directory,
there are detailed comments for all options:

```
(user)$ /data/bashvirt/bashvirt.sh tpl > /data/vms/win11/run.sh
```

Suppose you have already downloaded Windows 11 and VirtIO driver iso images to
`/data/downloads`, then edit the script with text editor:

```
#!/bin/bash

vmdir=/data/vms/win11

cpus=4
mem=8G
storage=80G
uefi=yes
hyperv=yes
tpm=yes
bootiso=/data/downloads/win11.iso
nonbootiso=/data/downloads/virtio.iso

source /data/bashvirt/bashvirt.sh
```

Run the script to lanuch virtual machine and install operating system:

```
(user)$ chmod u+x /data/vms/win11/run.sh
(user)$ /data/vms/win11/run.sh
```

If anything go wrong, it would generate a log file called `journal.txt`.

After installation finished, shutdown the virtual machine, edit the script
again, comment out the iso images part, or it would boot from iso every time:

```
...

#bootiso=~/Downloads/win11.iso
#nonbootiso=~/Downloads/virtio.iso
gpu=virtio

...
```

All Done.

## Options

Run `bashvirt.sh -h` to get help info.

```
usage: bashvirt.sh [actions]
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
```

