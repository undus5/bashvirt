#!/bin/bash

errf() { printf "${@}" >&2; exit 1; }

which evars.sh &>/dev/null || errf "evars.sh not found\n"
source $(which evars.sh)

print_help() {
    errf "Usage: $(basename ${0}) [a|d] <vmname> <device_name>\n"
}

vmname=${1}
devname=${2}
action=${3}
vmdir=${qvmdir}/${vmname}
vmexec="${vmdir}/run.sh"

case "${action}" in
    a)
        act="usb-attach"
        ;;
    d)
        act="usb-detach"
        ;;
    *)
        print_help
        ;;
esac

# devid=${!devname}
declare -n devid=${devname}
[[ -n "${devid}" ]] || errf "undefined device: ${devname}\n"

if [[ -d "${vmdir}" && -f "${vmexec}" ]]; then
    "${vmexec}" ${act} ${devid}
else
    errf "${vmname} not found\n"
fi

