--: vm configuratoin template

--: bootable live iso
-- bootiso = "path/to/windows.iso"

--: non-boot data iso
-- dataiso = "path/to/virtio.iso"

--: virtiofs shared folder between host and guest
-- viofsdir = "path/to/dir"

--: enable hyper-v enlightenments for windows guest
-- hyperv = true

--: use UEFI instead of BIOS
uefi = true

--: cpu cores
--: check physical cpu info 'cat /proc/cpuinfo'
cpus = 2

--: memory size
ram = "4G"

--: initial disk size
storage = "120G"

--: network cards mode, [qemu|nat|lan|natlan]
-- nic = "nat"

--: graphic card, [std|qxl|virtio]
gpu = "std"

--: display mode, [sdl|gtk]
display = "sdl"

--: enable tablet emulation
-- tablet = true

--: resolution
resolution = "1920x1080"

--: enable fullscreen
fullscreen = true

--: disk adapter [qemu|virtio]
disk_adapter = "virtio"

--: network adapter [qemu|virtio]
nic_adapter = "virtio"

--: disk image file, default is \${vmdir}/disk.qcow2, auto created if not exists
--disk = "path/to/disk.qcow2"

--: require for viofs, if guest user id is not 1000
--viofs_uid = 1001
--viofs_gid = 1001

--: additional qemu aguments
--qemu_args_extra = "..."
