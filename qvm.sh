#!/bin/bash

# _sdir=$(dirname $(realpath ${BASH_SOURCE[0]}))
errf() { printf "${@}" >&2; exit 1; }

which evars.sh &>/dev/null || errf "evars.sh not found\n"
source $(which evars.sh)

_vmname=${1}
_vmdir=${_qvmdir}/${_vmname}
_vmexec="${_vmdir}/run.sh"

if [[ "${_vmname}" == "--" ]]; then
    shift
    bashvirt.sh "${@}"
elif [[ -d "${_vmdir}" && -f "${_vmexec}" ]]; then
    shift
    "${_vmexec}" "${@}"
else
    errf "${_vmname} not found\n"
fi
