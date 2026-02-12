#!/bin/bash

errf() { printf "${@}" >&2; exit 1; }

# import ${qvmdir} variable
which evars.sh &>/dev/null || errf "evars.sh not found\n"
source $(which evars.sh)

vmname=${1}
vmdir=${qvmdir}/${vmname}
vmexec="${vmdir}/run.sh"

if [[ "${vmname}" == "--" ]]; then
    shift
    bashvirt.sh "${@}"
elif [[ -d "${vmdir}" && -x "${vmexec}" ]]; then
    shift
    "${vmexec}" "${@}"
else
    errf "${vmname} not found\n"
fi

