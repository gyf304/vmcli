PREFIX?=/usr/local

.PHONY: all clean install

VM_INSTALL_DIR=${VMCTLDIR}

all: build/vmcli build/vmctl build/test-vmctl

build:
	mkdir -p build

build/vmcli: build vmcli/Sources/vmcli/main.swift vmcli/Package.swift
	cd vmcli && swift build -c release --disable-sandbox
	cp vmcli/.build/release/vmcli build/vmcli
	codesign -s - --entitlements vmcli/vmcli.entitlements build/vmcli
	chmod +x build/vmcli

build/test-vmctl: build test-vmctl/Sources/test-vmctl/main.swift test-vmctl/Package.swift
	cd test-vmctl && swift build -c release --disable-sandbox
	cp test-vmctl/.build/release/test-vmctl build/test-vmctl
	chmod +x build/test-vmctl

build/vmctl: build vmctl/vmctl.sh
	cp vmctl/vmctl.sh build/vmctl
	chmod +x build/vmctl

clean:
	rm -rf build/vm/ubuntu/iso_folder
	rm -rf build/vm/ubuntu/seed.iso
	rm -rf build/vm/ubuntu/vm.conf
	rm -rf build/vm/ubuntu/.should-run

clean/vm:
	./cleanup.sh

install: all
	install -m 755 build/vmcli $(PREFIX)/bin/vmcli
	install -m 755 build/vmctl $(PREFIX)/bin/vmctl
	install -m 755 build/test-vmctl $(PREFIX)/bin/test-vmctl

install/vm/ubuntu: build/vm/ubuntu
	./install-vm.sh

build/vm: build
	mkdir -p build/vm

build/vm/ubuntu/.should-run:
	mkdir -p build/vm/ubuntu
	touch build/vm/ubuntu/.should-run

build/vm/ubuntu: build/vm build/vm/ubuntu/.should-run
	cd build/vm/ubuntu && ../../../vmbuilders/ubuntu.sh
