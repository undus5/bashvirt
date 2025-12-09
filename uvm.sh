#!/bin/bash

# _sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
eprintf() {
    printf "${@}" >&2
    exit 1
}

which qvars.sh &>/dev/null || eprintf "qvars.sh not found\n"
source $(which qvars.sh)

print_help() {
    eprintf "Usage: ${0} [a|d] _vmname _device_name\n"
}

_action=${1}
_vmname=${2}
_devname=_${3}
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
[[ -n "${!_devname}" ]] || eprintf "${_devname} is undefined\n"

if [[ -d "${_vmdir}" && -f "${_vmexec}" ]]; then
    "${_vmexec}" ${_act} ${!_devname}
else
    eprintf "${_vmname} not found\n"
fi
