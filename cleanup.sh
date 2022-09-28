#!/usr/bin/env sh

if [[ -z "${VMCTLDIR}" ]]; then
	printf "You need to run 'export VMCTLDIR=<path to your vm storage>'\n"
	exit 1
fi

# get full path to script
BASEDIR="${PWD}/$(dirname $0)"

# change into script directory
pushd $BASEDIR 2>&1 >/dev/null

rm -rf $VMCTLDIR/ubuntu/*

# go back to wherever we came from
popd 2>&1 >/dev/null
