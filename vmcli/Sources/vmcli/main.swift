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

var origStdinTerm : termios? = nil
var origStdoutTerm : termios? = nil

var vm : VZVirtualMachine? = nil

var stopRequested = false

// mask TERM signals so we can perform clean up
let signalMask = SIGPIPE | SIGINT | SIGTERM | SIGHUP
signal(signalMask, SIG_IGN)
let sigintSrc = DispatchSource.makeSignalSource(signal: signalMask, queue: .main)
sigintSrc.setEventHandler {
    quit(1)
}
sigintSrc.resume()

func setupTty() {
    if isatty(0) != 0 {
        origStdinTerm = termios()
        var term = termios()
        tcgetattr(0, &origStdinTerm!)
        tcgetattr(0, &term)
        cfmakeraw(&term)
        tcsetattr(0, TCSANOW, &term)
    }
}

func resetTty() {
    if origStdinTerm != nil {
        tcsetattr(0, TCSANOW, &origStdinTerm!)
    }
    if origStdoutTerm != nil {
        tcsetattr(1, TCSANOW, &origStdoutTerm!)
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

@available(macOS 12, *)
func openFolder(path: String, tag: String, readOnly: Bool) throws -> VZDirectorySharingDeviceConfiguration {
    let sharedDirectory = VZSharedDirectory(url: URL(fileURLWithPath: path), readOnly: readOnly)
    let vzDirShare = VZVirtioFileSystemDeviceConfiguration(tag: tag)
    vzDirShare.share = VZSingleDirectoryShare(directory: sharedDirectory)
    return vzDirShare
}

class OccurrenceCounter {
    let pattern: Data
    var i = 0
    init(_ pattern: Data) {
        self.pattern = pattern
    }

    func process(_ data: Data) -> Int {
        if pattern.count == 0 {
            return 0
        }
        var occurrences = 0
        for byte in data {
            if byte == pattern[i] {
                i += 1
                if i >= pattern.count {
                    occurrences += 1
                    i = 0
                }
            } else {
                i = 0
            }
        }
        return occurrences
    }
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

#if EXTRA_WORKAROUND_FOR_BIG_SUR
    // See comment below for similar #if
#else
    @available(macOS 12, *)
    @Option(name: [ .short, .customLong("folder")], help: "Folders to share")
    var folders: [String] = []
#endif

    @Option(name: [ .short, .customLong("network") ], help: """
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

    @Option(help: "Escape Sequence, when using a tty")
    var escapeSequence: String = "q"

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
        let vmSerialIn = Pipe()
        let vmSerialOut = Pipe()

        let vmConsoleCfg = VZVirtioConsoleDeviceSerialPortConfiguration()
        let vmSerialPort = VZFileHandleSerialPortAttachment(
            fileHandleForReading: vmSerialIn.fileHandleForReading,
            fileHandleForWriting: vmSerialOut.fileHandleForWriting
        )
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
        // The #available check still causes a runtime dyld error on macOS 11 (Big Sur),
        // apparently due to a Swift bug, so add an extra check to work around this until
        // the bug is resolved. See eg https://developer.apple.com/forums/thread/688678
#if EXTRA_WORKAROUND_FOR_BIG_SUR
#else
        if #available(macOS 12, *) {
            for folder in folders {
                let parts = folder.split(separator: ":")
                if parts.count > 3 {
                    throw ValidationError("Too many components in shared folder: \(folder)")
                }
                let path = String(parts[0])
                var tag = String(parts[0])
                var readOnly = false
                if parts.count > 1 {
                    tag = String(parts[1])
                }
                if parts.count > 2 {
                    readOnly = (parts[2] == "ro")
                }
                puts("Adding shared folder '\(path)' with tag \(tag), but be warned, this might be unstable.")
                try vmCfg.directorySharingDevices.append(openFolder(path: path, tag: tag, readOnly: readOnly))
            }
        }
#endif
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

        // disable stdin echo, disable stdin line buffer, disable ^C
        setupTty()

        // set up piping.
        var fullEscapeSequence = Data([0x1b]) // escape sequence always starts with ESC
        fullEscapeSequence.append(escapeSequence.data(using: .nonLossyASCII)!)
        let escapeSequenceCounter = OccurrenceCounter(fullEscapeSequence)
        FileHandle.standardInput.waitForDataInBackgroundAndNotify()
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSFileHandleDataAvailable, object: FileHandle.standardInput, queue: nil)
        {_ in
            let data = FileHandle.standardInput.availableData
            if origStdinTerm != nil && escapeSequenceCounter.process(data) > 0 {
                FileHandle.standardError.write("Escape sequence detected, exiting.\n".data(using: .utf8)!)
                quit(1)
            }
            vmSerialIn.fileHandleForWriting.write(data)
            if data.count > 0 {
                FileHandle.standardInput.waitForDataInBackgroundAndNotify()
            }
        }

        vmSerialOut.fileHandleForReading.waitForDataInBackgroundAndNotify()
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSFileHandleDataAvailable, object: vmSerialOut.fileHandleForReading, queue: nil)
        {_ in
            let data = vmSerialOut.fileHandleForReading.availableData
            FileHandle.standardOutput.write(data)
            if data.count > 0 {
                vmSerialOut.fileHandleForReading.waitForDataInBackgroundAndNotify()
            }
        }

        // start VM
        vm = VZVirtualMachine(configuration: vmCfg)
        vm!.delegate = delegate

        vm!.start(completionHandler: { (result: Result<Void, Error>) -> Void in
            switch result {
            case .success:
                return
            case .failure(let error):
                FileHandle.standardError.write(error.localizedDescription.data(using: .utf8)!)
                FileHandle.standardError.write("\n".data(using: .utf8)!)
                quit(1)
            }
        })

        RunLoop.main.run()
    }
}

VMCLI.main()
