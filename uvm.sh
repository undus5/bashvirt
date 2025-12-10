#!/bin/bash

# _sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
eprintf() {
    printf "${@}" >&2
    exit 1
}

which qvars.sh &>/dev/null || eprintf "qvars.sh not found\n"
source $(which qvars.sh)

print_help() {
    eprintf "Usage: $(basename ${0}) [a|d] _vmname _device_name\n"
}

_vmname=${1}
_devname=_${2}
_action=${3}
_vmdir=${_qvmdir}/${_vmname}
_vmexec="${_vmdir}/run.sh"

# _devid=${!_devname}
declare -n _devid=${_devname}

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
[[ -n "${_devid}" ]] || eprintf "undefined device: ${_devname}\n"

if [[ -d "${_vmdir}" && -f "${_vmexec}" ]]; then
    "${_vmexec}" ${_act} ${!_devname}
else
    eprintf "${_vmname} not found\n"
fi

