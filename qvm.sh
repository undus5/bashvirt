#!/usr/bin/bash

# _sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
eprintf() {
    printf "${@}" >&2
    exit 1
}

which qvdir.sh &>/dev/null || eprintf "qvdir.sh not found\n"
source $(which qvdir.sh)

_vmname=${1}
_vmdir=${_qvdir}/${_vmname}
_vmexec="${_vmdir}/run.sh"

if [[ "${_vmname}" == "--" ]]; then
    shift
    bashvirt.sh "${@}"
elif [[ -d "${_vmdir}" && -f "${_vmexec}" ]]; then
    shift
    "${_vmexec}" "${@}"
else
    eprintf "${_vmname} not found\n"
fi
