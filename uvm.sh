#!/bin/bash

errf() { printf "${@}" >&2; exit 1; }

# import ${qvmdir} variable
which evars.sh &>/dev/null || errf "evars.sh not found\n"
source $(which evars.sh)

print_help() { errf "Usage: $(basename ${0}) [a|d] <vmname> <device_name>\n"; }

action=${1}
vmname=${2}
devname=${3}
vmdir=${qvmdir}/${vmname}
vmexec="${vmdir}/run.sh"

case "${action}" in
    a)
        act="usb-attach"
        ;;
    d)
        act="usb-detach"
        ;;
    l)
        act="usb-list"
        ;;
    *)
        print_help
        ;;
esac

if [[ "${action}" != "l" ]]; then
    # devid=${!devname}
    declare -n devid=${devname}
    [[ -n "${devid}" ]] || errf "undefined device: ${devname}\n"
fi

if [[ -d "${vmdir}" && -x "${vmexec}" ]]; then
    "${vmexec}" ${act} ${devid}
else
    errf "${vmname} not found\n"
fi

