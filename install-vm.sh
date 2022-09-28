#!/usr/bin/env sh

if [[ -z "${VMCTLDIR}" ]]; then
	printf "You need to run 'export VMCTLDIR=<path to your vm storage>'\n"
	exit 1
fi

cp -r build/vm/ubuntu $VMCTLDIR
