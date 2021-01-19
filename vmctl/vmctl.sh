#!/bin/bash
set -e

script="$(basename $0)"

if [ "$VMCTLDIR" != "" ]; then
	pushd "$VMCTLDIR" > /dev/null
	VMCTLDIR="$(pwd)"
	popd > /dev/null
fi

function generate_mac {
	printf '%012x\n' "$(( 0x$(hexdump -e '6/1 "%02x" "\n"' -n 6 /dev/urandom) & 0xfeffffffffff | 0x020000000000 ))"
}

function get_ip_mac_assoc {
	arp -a \
		| cut -d ' ' -f 2,4 \
		| grep : \
		| sed 's/[\(\)]//g' \
		| sed 's/[: ]/ 0x/g' \
		| xargs -L 1 printf '%s %02x%02x%02x%02x%02x%02x\n'
}

function get_mac {
	file="$1"
	if [ ! -e "$file" ]; then
		generate_mac > "$file"
	fi
	cat "$file"
}

function format_mac {
	sed 's/.\{2\}/&:/g' | cut -d ":" -f 1-6
}

function compile_args {
	dir="$1"
	OLD_IFS="$IFS"
	IFS="="
	cmd=""
	netid="0"
	while read -r key value; do
		if [ "$key" = "network" ]; then
			if [ ! "$value" = *"@"* ]; then
				mac=$(get_mac "$dir/$netid.macaddr" | format_mac)
				cmd+=" --$key=\"$mac@$value\""
			fi
			netid=$(( $netid + 1 ))
		else
			cmd+=" '--$key=$value'"
		fi
	done < "$dir/vm.conf"
	IFS="$OLD_IFS"
	echo "$cmd"
}

function start {
	if [ "$1" = "" ]; then
		echo "missing argument" >&2
		exit 1
	fi
	dir="${1%/}"
	if [ "$VMCTLDIR" != "" ]; then
		dir="$VMCTLDIR/$dir"
	fi
	# wipe dead sockets
	SCREENDIR="$dir/screen" screen -wipe &> /dev/null || true
	# ...and check if any sockets are left
	if ! rmdir "$dir/screen" &> /dev/null ; then
		echo "VM already running" >&2
		exit 1
	fi
	args="$(compile_args "$dir")"
	SCREENDIR="$dir/screen" screen -dm sh -c "pushd \"$dir\" > /dev/null; vmcli $args"
}

function attach {
	if [ "$1" = "" ]; then
		echo "missing argument" >&2
		exit 1
	fi
	dir="${1%/}"
	if [ "$VMCTLDIR" != "" ]; then
		dir="$VMCTLDIR/$dir"
	fi
	SCREENDIR="$dir/screen" screen -r
}

function stop {
	if [ "$1" = "" ]; then
		echo "missing argument" >&2
		exit 1
	fi
	dir="${1%/}"
	if [ "$VMCTLDIR" != "" ]; then
		dir="$VMCTLDIR/$dir"
	fi
	if [ ! -e "$dir" ]; then
		exit 1
	fi
	# wait a bit until the screen directory is empty
	while ! rmdir "$dir/screen" &> /dev/null; do
		# input ESC-Q escape sequence
		SCREENDIR="$dir/screen" screen -X stuff $(printf "\033q")
		sleep 0.5
	done
}

function get_ip {
	if [ "$1" = "" ]; then
		echo "missing argument" >&2
		exit 1
	fi
	dir="${1%/}"
	if [ "$VMCTLDIR" != "" ]; then
		dir="$VMCTLDIR/$dir"
	fi
	if [ ! -e "$dir" ]; then
		exit 1
	fi
	assoc="$(get_ip_mac_assoc)"
	for addrfile in "$dir"/*.macaddr; do
		prefix="${addrfile%.macaddr}"
		ip=$(printf "%s" "$assoc" | grep "$(cat "$addrfile")" | cut -d ' ' -f 1)
		if [ "$ip" != "" ]; then
			printf "%s\n" "$ip" > "$prefix.ipaddr"
		fi
		cat "$prefix.ipaddr" || true
	done
}

function vm_ssh {
	ip=$(get_ip "$1" | head -n 1)
	if [ "$ip" = "" ]; then
		exit 1
	fi
	ssh "$ip"
}

action="$1"

if [ "$action" = "start" ]; then
	start "$2"
elif [ "$action" = "stop" ]; then
	stop "$2"
elif [ "$action" = "attach" ]; then
	attach "$2"
elif [ "$action" = "ip" ]; then
	get_ip "$2"
elif [ "$action" = "ssh" ]; then
	vm_ssh "$2"
else
	echo "usage: $script {start|stop|attach|ip|ssh} vm" > /dev/stderr
fi
