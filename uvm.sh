#!/bin/bash

# _sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
errf() {
    printf "${@}" >&2
    exit 1
}

which qvars.sh &>/dev/null || errf "qvars.sh not found\n"
source $(which qvars.sh)

print_help() {
    errf "Usage: $(basename ${0}) [a|d] _vmname _device_name\n"
}

_vmname=${1}
_devname=_${2}
_action=${3}
_vmdir=${_qvmdir}/${_vmname}
_vmexec="${_vmdir}/run.sh"

case "${_action}" in
    a)
        _act="usb-attach"
        ;;
    d)
        _act="usb-detach"
        ;;
    *)
        print_help
        ;;
esac

[[ -n "${_devname}" ]] || print_help
declare -n _devid=${_devname}
# _devid=${!_devname}
[[ -n "${_devid}" ]] || errf "undefined device: ${_devname}\n"

if [[ -d "${_vmdir}" && -f "${_vmexec}" ]]; then
    "${_vmexec}" ${_act} ${_devid}
else
    errf "${_vmname} not found\n"
fi

