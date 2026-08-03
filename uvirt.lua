#!/bin/lua

home_dir = os.getenv("HOME")
data_dir = home_dir .. "/uvirt.d"

self_path = debug.getinfo(1, "S").source:sub(2)
f = io.popen("realpath " .. self_path)
self_path = f:read("l")
f:close()

proj_dir = self_path:match("(.*/)"):sub(1, -2)

package.path = package.path .. string.format(";%s/?.lua", proj_dir)
require("init_configs")

help_info = [[
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
]]

function print_help ()
   io.write(help_info)
end

function dir_exists (path)
   -- appending a trailing slash works across both Unix and Windows systems
   local ok, err, code = os.rename(path .. "/", path .. "/")
   if not ok then
      if code == 13 then 
         -- code 13 means permission denied, but the directory DOES exist
         return true 
      end
      return false
   end
   return true
end

function file_exists (path)
   local f = io.open(path, "r")
   if f then
      f:close()
      return true
   else
      return false
   end
end

function create_vm (vm_name)
   if not vm_name then
      io.stderr:write("vm_name is undefined\n")
      os.exit(1)
   end
   local vm_dir = data_dir .. "/" .. vm_name
   if file_exists(vm_dir .. "/init.lua") then
      io.stderr:write(string.format("vm exists: %s\n", vm_name))
      os.exit(1)
   else
      os.execute("mkdir -p " .. vm_dir)
      local vm_init = vm_dir .. "/init.lua"
      local vm_init_tpl = proj_dir .. "/init_configs.lua"
      os.execute(string.format("cat %s > %s", vm_init_tpl, vm_init))
      print(string.format("created '%s'", vm_dir:gsub(home_dir, "~")))
   end
end

function list_running_vm ()
   local f = io.popen("pidof qemu-system-x86_64")
   local pids = f:read("l")
   f:close()
   if pids then
      f = io.popen("ps --no-headers -o command -p " .. pids)
      for l in f:lines() do
         local n = l:match("%-name %w+")
         if n then
            print(n:sub(7))
         end
      end
      f:close()
   end
end

sub_cmd = arg[1]
help_args = { help = 1, ["--help"] = 1, ["-h"] = 1 }

if sub_cmd == "create" then
   vm_name = arg[2]
   create_vm(vm_name)
   os.exit(0)
elseif sub_cmd == "ps" then
   list_running_vm()
   os.exit(0)
elseif help_args[sub_cmd] then
   print_help()
   os.exit(0)
end

if #arg == 0 then
   print_help()
   os.exit(1)
end

--------------------------------------------------------------------------------
-- vm_name
--------------------------------------------------------------------------------

package.path = package.path .. string.format(";%s/?/init.lua", data_dir)

vm_name = arg[1]
vm_dir = data_dir .. "/" .. vm_name

if not file_exists(vm_dir .. "/init.lua") then
   io.stderr:write(string.format("vm not found: %s\n", vm_name))
   os.exit(1)
end

require(vm_name)

function log_write (str)
   if not str then
      return false
   end
   local vm_log = vm_dir .. "/log.txt"
   local f = io.open(vm_log, "a")
   f:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), str))
   f:close()
end

function out_write (str)
   if not str then
      return false
   end
   log_write(str)
   io.stdout:write(str .. "\n")
end

function err_write (str)
   if not str then
      return false
   end
   log_write(str)
   io.stderr:write(str .. "\n")
   os.exit(1)
end

qemu_args = " -enable-kvm -machine q35 -name " .. vm_name

--------------------------------------------------------------------------------
-- qemu pid
--------------------------------------------------------------------------------

pid_file = vm_dir .. "/qemu.pid"

qemu_args = qemu_args .. " -pidfile " .. pid_file

function is_pid_proc (pid, proc_name)
   local cmdl = "ps -o command= -p %s | grep " .. proc_name
   local f = io.popen(string.format(cmdl, pid))
   local p = f:read("l")
   f:close()
   if p then
      return true
   else
      return false
   end
end

function qemu_pid ()
   local f = io.open(pid_file, "r")
   local pid
   if f then
      pid = f:read("l")
      f:close()
   end
   if pid and is_pid_proc(pid, "qemu-system-x86_64") then
      return pid
   end
   return nil
end

--------------------------------------------------------------------------------
-- monitor
--------------------------------------------------------------------------------

monitor_sock = vm_dir .. "/monitor.sock"

qemu_args = qemu_args .. " -monitor unix:%s,server,nowait"
qemu_args = string.format(qemu_args, monitor_sock)

function monitor_execute (cmd)
   local sock_exists = os.execute("test -S " .. monitor_sock)
   if sock_exists then
      local cmdl = "echo '%s' | socat - unix-connect:%s"
      cmdl = string.format(cmdl, cmd, monitor_sock)
      cmdl = cmdl .. " | tail --lines=+2 | grep -v '^(qemu)'"
      local f = io.popen(cmdl)
      for l in f:lines() do
         print(l)
      end
      f:close()
   end
end

--------------------------------------------------------------------------------
-- sub_cmd
--------------------------------------------------------------------------------

sub_cmd = arg[2]

function kill_vm ()
   local pid = qemu_pid()
   if pid then
      os.execute("kill -9 " .. pid)
   end
end

function reset_vm ()
   monitor_execute("system_reset")
end

function tty ()
   local num = arg[3]
   if not num or not num:match("^[1-7]$") then
      err_write("invalid tty number, require [1-7]")
   end
   monitor_execute("sendkey ctrl-alt-f" .. num)
end

function usb_list ()
   monitor_execute("info usb")
end

function split_usb_device_ids ()
   local device_id = arg[3]
   if not device_id or not device_id:match("%w%w%w%w:%w%w%w%w") then
      err_write("invalid usb device_id, refer to help info")
   end
   local ids = {}
   for id in device_id:gmatch("([^:]+)") do
      table.insert(ids, id)
   end
   return ids
end

function usb_attach ()
   local ids = split_usb_device_ids(device_id)
   local assigned_id = "usb" .. ids[1] .. ids[2]
   local cmdl = "device_add usb-host,vendorid=0x%s,productid=0x%s,id=%s"
   cmdl = string.format(cmdl, ids[1], ids[2], assigned_id)
   monitor_execute(cmdl)
end

function usb_detach ()
   local ids = split_usb_device_ids(device_id)
   local assigned_id = "usb" .. ids[1] .. ids[2]
   monitor_execute("device_del " .. assigned_id)
end

cmds = {
   kill = kill_vm, reset = reset_vm, tty = tty,
   ul = usb_list, ua = usb_attach, ud = usb_detach
}

if cmds[sub_cmd] then
   cmds[sub_cmd]()
   os.exit(0)
end

if sub_cmd and sub_cmd ~= "dry" then
   err_write("invalid sub_cmd, refer to help info")
end

--------------------------------------------------------------------------------
-- cpu, ram
--------------------------------------------------------------------------------

cpu_model = "host"

f = io.popen("cat /proc/cpuinfo | grep 'AuthenticAMD'| head -n 1")
is_amd = f:read("l")
f:close()

if is_amd then
   cpu_model = cpu_model .. ",topoext=on"
end

if hyperv then
   if type(hyperv) ~= "boolean" then
      err_write("invalid option: hyperv, require boolean")
   end
   cpu_model = cpu_model .. ",hv_relaxed,hv_vapic,hv_spinlocks=0xfff"
   cpu_model = cpu_model .. ",hv_vpindex,hv_synic,hv_time,hv_stimer"
   cpu_model = cpu_model .. ",hv_tlbflush,hv_tlbflush_ext,hv_ipi"
   cpu_model = cpu_model .. ",hv_avic,hv_xmm_input,hv_stimer_direct"
   cpu_model = cpu_model .. ",hv_runtime,hv_frequencies,hv_reenlightenment"
   cpu_model = cpu_model .. " -rtc base=localtime"
end

qemu_args = qemu_args .. " -cpu " .. cpu_model

cmdl = "cat /proc/cpuinfo | grep 'cpu cores'| head -n 1"
cmdl = cmdl .. " | cut -d: -f2 | tr -d '[[:space:]]'"

f = io.popen(cmdl)
max_cores = tonumber(f:read("l"))
f:close()

if type(cpus) ~= "number" or cpus > max_cores then
   err_write("invalid option: cpus, require number and less than " .. max_cores)
end

qemu_args = qemu_args .. " -smp " .. cpus

if not ram:match("^%d+[GM]$") then
   err_write("invalid option: ram, require format '4G' or '512M'")
end

qemu_args = qemu_args .. " -m " .. ram

--------------------------------------------------------------------------------
-- uefi
--------------------------------------------------------------------------------

-- fedora
ovmf_code = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
ovmf_vars = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
-- arch
if not file_exists(ovmf_code) then
   ovmf_code = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
end
if not file_exists(ovmf_vars) then
   ovmf_vars = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
end

ovmf_vars_vm = vm_dir .. "/OVMF_VARS.fd"

if uefi then
   if type(uefi) ~= "boolean" then
      err_write("invalid option: uefi, require boolean")
   end
   if not file_exists(ovmf_vars_vm) then
      os.execute(string.format("cp %s %s", ovmf_vars, ovmf_vars_vm))
   end
   uefi_args = " -drive if=pflash,format=raw,readonly=on,file=%s"
   uefi_args = uefi_args .. " -drive if=pflash,format=raw,file=%s"
   uefi_args = string.format(uefi_args, ovmf_code, ovmf_vars_vm)
   qemu_args = qemu_args .. uefi_args
end

--------------------------------------------------------------------------------
-- disk
--------------------------------------------------------------------------------

if not storage:match("^%d+[GM]$") then
   err_write("invalid option: storage, require format '80G' or '512M'")
end

if not disk then
   disk = vm_dir .. "/disk.qcow2"
end

if disk:match("%.qcow2$") then
   disk_fmt = "qcow2"
else
   disk_fmt = "raw"
end

if not file_exists(disk) then
   cmdl = string.format(
      "qemu-img create -f %s -o nocow=on %s %s",
      disk_fmt, disk, storage
   )
   if os.execute(cmdl .. " >/dev/null") then
      out_write(string.format("created '%s'", disk:gsub(home_dir, "~")))
   end
end

disk_devices = { qemu = "ide-hd", virtio = "virtio-blk" }

if not disk_devices[disk_adapter] then
   err_write("invalid option: disk_adapter, require: [qemu|virtio]")
end

disk_args = " -device %s,drive=disk0,bootindex=1"
disk_args = disk_args .. " -drive if=none,id=disk0,format=%s,file=%s"
disk_args = string.format(disk_args, disk_devices[disk_adapter], disk_fmt, disk)
if disk_adapter == "qemu" then
   disk_args = disk_args .. ",bus=ahci0.0 -device ahci,id=ahci0"
end

qemu_args = qemu_args .. disk_args

--------------------------------------------------------------------------------
-- network card
--------------------------------------------------------------------------------

nic_options = { qemu = 1, nat = 1, lan = 1, natlan = 1 }

if nic and not nic_options[nic] then
   err_write("invalid option: nic, require: [qemu|nat|lan|natlan]")
end

nic_devices = { qemu = "e1000e", virtio = "virtio-net-pci" }

if not nic_devices[nic_adapter] then
   err_write("invalid option: nic_adapter, require: [qemu|virtio]")
end

function mac_addr (s)
   local f = io.popen(string.format("printf '%s' | sha256sum", vm_name .. s))
   local h = f:read("l")
   f:close()
   local addr = "52:54:%s:%s:%s:%s"
   return string.format(addr, h:sub(1,2), h:sub(3,4), h:sub(5,6), h:sub(7,8))
end

if nic == "qemu" then
   nic_args = " -nic user,model=%s,mac=%s"
   nic_args = string.format(nic_args, nic_devices[nic_adapter], mac_addr("user"))
end

if nic == "nat" then
   nic_args = " -nic bridge,br=brnat,model=%s,mac=%s"
   nic_args = string.format(nic_args, nic_devices[nic_adapter], mac_addr("brnat"))
end

if nic == "lan" then
   nic_args = " -nic bridge,br=brlan,model=%s,mac=%s"
   nic_args = string.format(nic_args, nic_devices[nic_adapter], mac_addr("brlan"))
end

if nic == "natlan" then
   nic_args = " -nic bridge,br=brnat,model=%s,mac=%s"
   nic_args = string.format(nic_args, nic_devices[nic_adapter], mac_addr("brnat"))
   nic_args = nic_args .. " -nic bridge,br=brlan,model=%s,mac=%s"
   nic_args = string.format(nic_args, nic_devices[nic_adapter], mac_addr("brlan"))
end

if nic_args then
   qemu_args = qemu_args .. nic_args
end

--------------------------------------------------------------------------------
-- iso
--------------------------------------------------------------------------------

if bootiso then
   if file_exists(bootiso) then
      iso_args = " -drive if=none,id=cd0,media=cdrom,file=" .. bootiso
      iso_args = iso_args .. " -device ide-cd,drive=cd0,bootindex=0"
   else
      err_write("file not found: " .. bootiso)
   end
end

if dataiso then
   if file_exists(dataiso) then
      if not iso_args then
         iso_args = ""
      end
      iso_args = iso_args .. " -drive media=cdrom,file=" .. dataiso
   else
      err_write("file not found: " .. dataiso)
   end
end

if iso_args then
   qemu_args = qemu_args .. iso_args
end

--------------------------------------------------------------------------------
-- graphic card
--------------------------------------------------------------------------------

if not resolution:match("^%d+x%d+$") then
   err_write("invalid option: resolution, require format '1920x1080'")
end

pixels = {}
for n in resolution:gmatch("([^x]+)") do
   table.insert(pixels, n)
end

res_args = "xres=%s,yres=%s"
res_args = string.format(res_args, pixels[1], pixels[2])

gpu_devices = { std = "VGA", qxl = "qxl", virtio = "virtio-vga-gl" }

if gpu then
   if not gpu_devices[gpu] then
      err_write("invalid option: gpu, require: [std|qxl|virtio]")
   end
   gpu_args = string.format(" -device %s,%s", gpu_devices[gpu], res_args)
end

if gpu_args then
   qemu_args = qemu_args .. gpu_args
end

--------------------------------------------------------------------------------
-- display
--------------------------------------------------------------------------------

display_devices = { sdl = 1, gtk = 1 }

usb_args = " -device qemu-xhci"
display_args = usb_args

if display then
   if not display_devices[display] then
      err_write("invalid option: display, require: [sdl|gtk]")
   end
   display_args = display_args .. " -display " .. display .. ",gl=on"

   if fullscreen then
      if type(fullscreen) ~= "boolean" then
         err_write("invalid option: fullscreen, require boolean")
      end
      display_args = display_args .. ",full-screen=on"
   end

   if tablet then
      if type(tablet) ~= "boolean" then
         err_write("invalid option: tablet, require boolean")
      end
      display_args = display_args .. " -device usb-tablet"
   end
end

qemu_args = qemu_args .. display_args

--------------------------------------------------------------------------------
-- audio
--------------------------------------------------------------------------------

audio_args = " -device ich9-intel-hda -device hda-output,audiodev=snd0"
audio_args = audio_args .. " -audiodev pipewire,id=snd0"

qemu_args = qemu_args .. audio_args

--------------------------------------------------------------------------------
-- virtiofs
--------------------------------------------------------------------------------

-- fedora
viofsd_exec = "/usr/libexec/virtiofsd"
-- arch
if not file_exists(viofsd_exec) then
   viofsd_exec = "/usr/lib/virtiofsd"
end

viofsd_sock = vm_dir .. "/virtiofsd.sock"
viofsd_pidfile = vm_dir .. "/virtiofsd.pid"
viofsd_tag = "Shared"

if viofsdir and dir_exists(viofsdir) then
   viofsd_args = " -object memory-backend-memfd,id=memfd,share=on,size=%s"
   viofsd_args = viofsd_args .. " -numa node,memdev=memfd"
   viofsd_args = viofsd_args .. " -chardev socket,id=vfsc,path=%s"
   viofsd_args = viofsd_args .. " -device vhost-user-fs-pci,chardev=vfsc,tag=%s"
   viofsd_args = string.format(viofsd_args, ram, viofsd_sock, viofsd_tag)
end

if viofsd_args then
   qemu_args = qemu_args .. viofsd_args
end

function start_viofsd ()
   if not viofsdir then
      return false
   end

   local pid, f

   if file_exists(viofsd_pidfile) then
      f = io.open(viofsd_pidfile, "r")
      pid = f:read("l")
      f:close()
   end

   if not pid or not is_pid_proc(pid, virtiofsd) then
      local guest_uid = 1000
      local guest_gid = 1000
      if viofs_uid then
         guest_uid = viofs_uid
      end
      if viofs_gid then
         guest_gid = viofs_gid
      end

      local host_uid, host_gid
      f = io.popen("id -u")
      host_uid = f:read("l")
      f:close()
      f = io.popen("id -g")
      host_gid = f:read("l")
      f:close()

      local cmdl = "nohup " .. viofsd_exec .. " --sandbox namespace"
      cmdl = cmdl .. " --socket-path " .. viofsd_sock
      cmdl = cmdl .. " --shared-dir " .. viofsdir
      cmdl = cmdl .. " --translate-uid host:%s:%s:1"
      cmdl = string.format(cmdl, host_uid, guest_uid)
      cmdl = cmdl .. " --translate-gid host:%s:%s:1"
      cmdl = string.format(cmdl, host_gid, guest_gid)
      cmdl = cmdl .. " --translate-uid squash-guest:0:%s:4294967295"
      cmdl = string.format(cmdl, host_uid)
      cmdl = cmdl .. " --translate-gid squash-guest:0:%s:4294967295"
      cmdl = string.format(cmdl .. " &>/dev/null &", host_gid)
      os.execute(cmdl)
   end
end

-- function stop_viofsd ()
--    local pid, f
--    if file_exists(viofsd_pidfile) then
--       f = io.open(viofsd_pidfile, "r")
--       pid = f:read("l")
--       f:close()
--    end
--    if pid and is_pid_proc(pid, virtiofsd) then
--       os.execute("kill -9 " .. pid)
--    end
-- end

--------------------------------------------------------------------------------
-- start vm
--------------------------------------------------------------------------------

cmdl = "qemu-system-x86_64" .. qemu_args

if sub_cmd == "dry" then
   print(cmdl)
   os.exit(0)
end

if qemu_pid() then
   err_write("vm is running")
end

start_viofsd()

f = io.popen(cmdl)
for l in f:lines() do
   out_write(l)
end
f:close()
