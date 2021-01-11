import Foundation
import ArgumentParser
import Virtualization

enum BootLoader: String, ExpressibleByArgument {
    case linux
}

enum SizeSuffix: UInt64, ExpressibleByArgument {
    case none = 1,
         KB = 1000, KiB = 0x400,
         MB = 1000000, MiB = 0x100000,
         GB = 1000000000, GiB = 0x40000000
}

var origTerm : termios? = nil

// mask TERM signal so we can perform clean up
let signalMask = SIGPIPE | SIGINT | SIGTERM | SIGHUP
signal(signalMask, SIG_IGN)
let sigintSrc = DispatchSource.makeSignalSource(signal: signalMask, queue: .main)
sigintSrc.setEventHandler {
    quit(1)
}
sigintSrc.resume()

func setupTty() {
    if isatty(0) != 0 {
        origTerm = termios()
        var term = termios()
        tcgetattr(0, &origTerm!)
        tcgetattr(0, &term)
        term.c_lflag = term.c_lflag & ~UInt(ECHO) & ~UInt(ICANON);
        assert(VINTR == 8)
        term.c_cc.8 = 0
        tcsetattr(0, TCSANOW, &term)
    }
}

func resetTty() {
    if origTerm != nil {
        tcsetattr(0, TCSANOW, &origTerm!)
    }
}

func quit(_ code: Int32) -> Never {
    resetTty()
    return exit(code)
}

func openDisk(path: String, readOnly: Bool) throws -> VZVirtioBlockDeviceConfiguration {
    let vmDiskURL = URL(fileURLWithPath: path)
    let vmDisk: VZDiskImageStorageDeviceAttachment
    do {
        vmDisk = try VZDiskImageStorageDeviceAttachment(url: vmDiskURL, readOnly: readOnly)
    } catch {
        throw error
    }
    let vmBlockDevCfg = VZVirtioBlockDeviceConfiguration(attachment: vmDisk)
    return vmBlockDevCfg
}

class VMCLIDelegate: NSObject, VZVirtualMachineDelegate {
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        quit(0)
    }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        quit(1)
    }
}

let delegate = VMCLIDelegate()

let vmCfg = VZVirtualMachineConfiguration()

struct VMCLI: ParsableCommand {
    @Option(name: .shortAndLong, help: "CPU count")
    var cpuCount: Int = 1

    @Option(name: .shortAndLong, help: "Memory Bytes")
    var memorySize: UInt64 = 512 // 512 MiB default

    @Option(name: .long, help: "Memory Size Suffix")
    var memorySizeSuffix: SizeSuffix = SizeSuffix.MiB

    @Option(name: [ .short, .customLong("disk") ], help: "Disks to use")
    var disks: [String] = []

    @Option(name: [ .customLong("cdrom") ], help: "CD-ROMs to use")
    var cdroms: [String] = []

    @Option(name: [ .short, .customLong("network") ],help: """
Networks to use. e.g. aa:bb:cc:dd:ee:ff@nat for a nat device, \
or ...@en0 for bridging to en0. \
Omit mac address for a generated address.
""")
    var networks: [String] = [ "nat" ]

    @Option(help: "Enable / Disable Memory Ballooning")
    var balloon: Bool = true

    @Option(name: .shortAndLong, help: "Bootloader to use")
    var bootloader: BootLoader = BootLoader.linux

    @Option(name: .shortAndLong, help: "Kernel to use")
    var kernel: String?

    @Option(help: "Initrd to use")
    var initrd: String?

    @Option(help: "Kernel cmdline to use")
    var cmdline: String?

    mutating func run() throws {
        vmCfg.cpuCount = cpuCount
        vmCfg.memorySize = memorySize * memorySizeSuffix.rawValue

        // set up bootloader
        switch bootloader {
        case BootLoader.linux:
            if kernel == nil {
                throw ValidationError("Kernel not specified")
            }
            let vmKernelURL = URL(fileURLWithPath: kernel!)
            let vmBootLoader = VZLinuxBootLoader(kernelURL: vmKernelURL)
            if initrd != nil {
                vmBootLoader.initialRamdiskURL = URL(fileURLWithPath: initrd!)
            }
            if cmdline != nil {
                vmBootLoader.commandLine = cmdline!
            }
            vmCfg.bootLoader = vmBootLoader
        }

        // set up tty
        let fin = FileHandle(fileDescriptor: 0)
        let fout = FileHandle(fileDescriptor: 1)

        // disable stdin echo, disable stdin line buffer, disable ^C
        // TODO: properly handle escape sequences
        setupTty()

        let vmConsoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
        let vmSerialPort = VZFileHandleSerialPortAttachment(fileHandleForReading: fin, fileHandleForWriting: fout)
        vmConsoleCfg.attachment = vmSerialPort
        vmCfg.serialPorts = [ vmConsoleCfg ]

        // set up storage
        // TODO: better error handling
        vmCfg.storageDevices = []
        for disk in disks {
            try vmCfg.storageDevices.append(openDisk(path: disk, readOnly: false))
        }
        for cdrom in cdroms {
            try vmCfg.storageDevices.append(openDisk(path: cdrom, readOnly: true))
        }

        // set up networking
        // TODO: better error handling
        vmCfg.networkDevices = []
        for network in networks {
            let netCfg = VZVirtioNetworkDeviceConfiguration()
            let parts = network.split(separator: "@")
            var device = String(parts[0])
            if parts.count > 1 {
                netCfg.macAddress = VZMACAddress(string: String(parts[0]))!
                device = String(parts[1])
            }
            switch device {
            case "nat":
                netCfg.attachment = VZNATNetworkDeviceAttachment()
            default:
                for iface in VZBridgedNetworkInterface.networkInterfaces {
                    if iface.identifier == network {
                        netCfg.attachment = VZBridgedNetworkDeviceAttachment(interface: iface)
                        break
                    }
                }
                if netCfg.attachment == nil {
                    throw ValidationError("Cannot find network: \(network)")
                }
            }
            vmCfg.networkDevices.append(netCfg)
        }

        // set up memory balloon
        let balloonCfg = VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        vmCfg.memoryBalloonDevices = [ balloonCfg ]

        vmCfg.entropyDevices = [ VZVirtioEntropyDeviceConfiguration() ]

        try vmCfg.validate()

        // start VM
        let vm = VZVirtualMachine(configuration: vmCfg)
        vm.delegate = delegate

        vm.start(completionHandler: { (result: Result<Void, Error>) -> Void in
            switch result {
            case .success:
                return
            case .failure:
                quit(1)
            }
        })
        RunLoop.main.run()
    }
}

VMCLI.main()
