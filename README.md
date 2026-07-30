# uvirt

A QEMU VM launcher written in lua, optimized for personal use.

## Features

- support bridged network and host-only network
- file sharing with host via [virtiofsd](https://virtio-fs.gitlab.io/)
- all data stored under `~/uvirt.d`.
- tested on fedora and archlinux

If you want to learn the details of what the script actually do, read the blog
post [QEMU/KVM Windows 11 Guest](https://undus.net/posts/qemu-kvm-win11-guest/)

## Usage

Create VM:

```
(user)$ uvirt.lua create myvm1
```

Then edit `~/uvirt.d/myvm1/init.lua` to fit what you need.

Start VM:

```
(user)$ uvirt.lua myvm1
```

If anything go wrong, there would be a log file at `~/uvirt.d/myvm1/log.txt`.

## Options

```
usage: uvirt.lua <create> <vm_name>
       uvirt.lua <tpl|ls>
       uvirt.lua <vm_name> [sub_cmd] [args]
options:
   create <vm_name>   create vm in ~/uvirt.d/
   ps                 list running virtual machines
   help,--help,-h     help info
sub_cmd:
   [empty]            boot virtual machine
   kill               kill virtual machine
   reset              reset virtual machine
   tty [1-7]          send key combo ctrl-alt-f[1-7]
   ul                 list attached devices
   ua <device_id>     passthrough usb device
   ud <device_id>     detach usb device
device_id:
   looks like '0853:0100', run 'lsusb' to get ('usbutils' package)
```
