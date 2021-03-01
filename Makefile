PREFIX?=/usr/local

.PHONY: all clean install

all: build/vmcli build/vmctl

build:
	mkdir -p build

build/vmcli: build vmcli/Sources/vmcli/main.swift vmcli/Package.swift
	cd vmcli && swift build -c release --disable-sandbox
	cp vmcli/.build/release/vmcli build/vmcli
	codesign -s - --entitlements vmcli/vmcli.entitlements build/vmcli
	chmod +x build/vmcli

build/vmctl: build vmctl/vmctl.sh
	cp vmctl/vmctl.sh build/vmctl
	chmod +x build/vmctl

clean:
	rm -rf build

install: all
	install -m 755 build/vmcli $(PREFIX)/bin/vmcli
	install -m 755 build/vmctl $(PREFIX)/bin/vmctl

build/vm: build
	mkdir -p build/vm

build/vm/ubuntu: build/vm
	mkdir -p build/vm/ubuntu
	cd build/vm/ubuntu && ../../../vmbuilders/ubuntu.sh
