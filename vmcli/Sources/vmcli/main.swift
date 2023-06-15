import Foundation
import ArgumentParser
import Virtualization

enum BootLoader: String, ExpressibleByArgument {
    case linux
    @available(macOS 13, *)
    case efi
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

// mask TERM signals so we can perform clean up
signal(SIGPIPE, SIG_IGN)
signal(SIGHUP, SIG_IGN)
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let sigSrcs = [
    SIGPIPE: DispatchSource.makeSignalSource(signal: SIGPIPE, queue: .main),
    SIGHUP: DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main),
    SIGINT: DispatchSource.makeSignalSource(signal: SIGINT, queue: .main),
    SIGTERM: DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main),
]
for (_, sigSrc) in sigSrcs {
    sigSrc.setEventHandler {
        quit(1)
    }
    sigSrc.resume()
}

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

func tryGracefulShutdown(timeout: Double) {
    if vm != nil && vm!.canRequestStop {
        do {
            try vm!.requestStop()
            // Wait for 'graceful' shutdown, but quit immediately if timeout reached
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                FileHandle.standardError.write("Shutdown timeout expired, exiting immediately.\r\n".data(using: .utf8)!)
                quit(1)
            }
        } catch {
            FileHandle.standardError.write("Failed to request stop.\r\n".data(using: .utf8)!)
            quit(1)
        }
    } else {
        quit(1)
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

    @Option(name: .shortAndLong, help: "EFI variable store location (EFI bootloader only)")
    var efiVars: String?

    @Option(name: .shortAndLong, help: "Kernel to use (Linux bootloader only)")
    var kernel: String?

    @Option(help: "Initrd to use (Linux bootloader only)")
    var initrd: String?

    @Option(help: "Kernel cmdline to use (Linux bootloader only)")
    var cmdline: String?

    @Option(help: "Escape Sequence, when using a tty")
    var escapeSequence: String = "q"

    @Option(help: "Timeout in seconds for graceful shutdown")
    var shutdownTimeout: Double = 120.0

    mutating func run() throws {
        vmCfg.cpuCount = cpuCount
        vmCfg.memorySize = memorySize * memorySizeSuffix.rawValue

        // set up bootloader
        switch bootloader {
        case BootLoader.linux:
            if kernel == nil {
                throw ValidationError("Kernel not specified")
            }
            if efiVars != nil {
                throw ValidationError("EFI variable store cannot be used with Linux bootloader")
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
        case BootLoader.efi:
            if #available(macOS 13, *) {
                if efiVars == nil {
                    throw ValidationError("EFI variable store must be specified if using EFI bootloader")
                }
                if kernel != nil || initrd != nil || cmdline != nil {
                    throw ValidationError("Kernel, initrd and cmdline options cannot be used with EFI bootloader")
                }
                let efiVarStoreURL = URL(fileURLWithPath: efiVars!)
                var efiVarStore: VZEFIVariableStore
                if FileManager.default.fileExists(atPath: efiVars!) {
                    efiVarStore = VZEFIVariableStore(url: efiVarStoreURL)
                } else {
                    efiVarStore = try VZEFIVariableStore(creatingVariableStoreAt: efiVarStoreURL)
                }
                let vmBootLoader = VZEFIBootLoader()
                vmBootLoader.variableStore = efiVarStore
                vmCfg.bootLoader = vmBootLoader
            } else {
                throw ValidationError("EFI bootloader is only available on macOS 13 and later versions")
            }
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

        if #available(macOS 13, *) {
            do {
                try VZVirtioFileSystemDeviceConfiguration.validateTag("rosetta")
                let rosettaDirectoryShare = try VZLinuxRosettaDirectoryShare()
                let fileSystemDevice = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
                fileSystemDevice.share = rosettaDirectoryShare

                vmCfg.directorySharingDevices.append(fileSystemDevice)
            } catch VZError.invalidVirtualMachineConfiguration {
                // Rosetta is unavailable.
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
        {[shutdownTimeout] _ in
            let data = FileHandle.standardInput.availableData
            if origStdinTerm != nil && escapeSequenceCounter.process(data) > 0 {
                FileHandle.standardError.write("Escape sequence detected, exiting.\r\n".data(using: .utf8)!)
                tryGracefulShutdown(timeout: shutdownTimeout)
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

        sigSrcs[SIGTERM]!.setEventHandler { [shutdownTimeout] in
            tryGracefulShutdown(timeout: shutdownTimeout)
        }
        sigSrcs[SIGINT]!.setEventHandler { [shutdownTimeout] in
            tryGracefulShutdown(timeout: shutdownTimeout)
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
