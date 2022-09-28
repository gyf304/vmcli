import ColorizeSwift
import Files
import Foundation

/// Struct designed to model a virtual machine and it's capabilities.
struct VM {
  var name: String

  /// Function used to start up a virtual machine for use.
  func start() {
    guard let config = readConfigFromDisk() else {
      print("Unable to start vm named \(name), vm.conf could not be read.")
      exit(1)
    }

    guard let macaddr = getMacAddress() else {
      print("Unable to start vm named \(name), mac address could not be retrieved.")
      exit(1)
    }

    guard let vmDirectoryPath = getVmDirectoryPath() else {
      print("Unable to start vm named \(name), configuration directory does not exist.")
      exit(1)
    }

    Shell.wipeScreenDeadSockets(vmDirectoryPath)

    if VM.vmIsRunning(atPath: "\(vmDirectoryPath)") {
      print("VM named \(name) is already running")
      exit(1)
    }

    let commandArgs = Self.configDataToString(data: config, macaddr: macaddr)

    Shell.vmcli(vmDirectoryPath, args: commandArgs)

    if VM.vmIsRunning(atPath: "\(vmDirectoryPath)") {
      print("VM \(name) was started")
    }
  }

  /// Function used to start an interactive ssh session with a virtual machine.
  func ssh() {
    guard let ip = getIp() else {
      print("Unable to ssh into vm named \(name), ip address could not be retrieved.")
      exit(1)
    }

    Shell.ssh(ip)
  }

  /// Function used to stop a virtual machine.
  func stop() {
    guard let ip = getIp() else {
      print("Unable to stop vm named \(name), ip address could not be retrieved.")
      exit(1)
    }

    let output = Shell.sshRunCommand(ip, command: "sudo shutdown -h now")

    print(output)
  }

  /// Function to attach directly to the virtual machine process.
  func attach() {
    if let vmDirectoryPath = getVmDirectoryPath() {
      Shell.attachToVMScreen(vmDirectoryPath)
    }
  }

  /// Function to retrieve the IP address associated with a virtual machine.
  func getIp() -> String? {
    if let vmDirectoryPath = getVmDirectoryPath() {
      let ipFilePath = "\(vmDirectoryPath)/0.ipaddr"

      if let ipAddress = try? NSString(contentsOfFile: ipFilePath, encoding: String.Encoding.utf8.rawValue) {
        return (ipAddress as String).trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        if let macaddr = getMacAddress(formatted: false) {
          let output: String = Shell.arpTable()
          let pattern = "(.*)\\s\(macaddr)"
          let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
          )

          if let match = regex?.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.utf8.count)) {
            if let ipRange = Range(match.range(at: 1), in: output) {
              let ipAddress = output[ipRange]
              let ipAddressString = String(ipAddress).trimmingCharacters(in: .whitespacesAndNewlines)
              let data = ipAddressString.data(using: .utf8)
              FileManager.default.createFile(atPath: ipFilePath, contents: data)

              return ipAddressString
            }
          }
        }
      }
    }

    return .none
  }

  /// Function used to retrieve a mac address for a virtual machine.
  ///
  /// - Parameters:
  ///   - formatted: Boolean value that determines if we do any formatting for the mac address (e.g. separate each octet with colons)
  ///
  func getMacAddress(formatted: Bool = true) -> String? {
    guard let vmDirectoryPath = getVmDirectoryPath() else {
      return .none
    }

    let macaddrFilePath = "\(vmDirectoryPath)/0.macaddr"

    guard let macaddr = try? NSString(contentsOfFile: macaddrFilePath, encoding: String.Encoding.utf8.rawValue) else {
      return .none
    }

    if !formatted {
      return (macaddr as String)
    }

    let formattedString = (macaddr as String).trimmingCharacters(in: .whitespacesAndNewlines)
      .reduce([]) { previous, char in
        previous + [String(char)]
      }.chunked(by: 2).compactMap { arr in
        arr.joined(separator: "")
      }.joined(separator: ":")

    return formattedString
  }

  /// Function used to retrieve a directory associated with a specific virtual machine.
  func getVmDirectoryPath() -> String? {
    guard let vmctldir = ProcessInfo.processInfo.environment["VMCTLDIR"] else {
      return .none
    }

    return "\(vmctldir)/\(name)"
  }

  /// Function used to retrieve the status of all virtual machines.
  static func printListOfVms() {
    if let vmctldir = ProcessInfo.processInfo.environment["VMCTLDIR"] {
      let fileManager = FileManager.default

      do {
        if fileManager.fileExists(atPath: vmctldir) {
          let vmctldirUrl = URL(fileURLWithPath: vmctldir)
          let subDirs = try vmctldirUrl.subDirectories()

          let sortedSubDirs = subDirs.sorted { $0.path < $1.path }

          for subdir in sortedSubDirs {
            var status = "● stopped".red()

            Shell.wipeScreenDeadSockets(subdir.path)

            if vmIsRunning(atPath: "\(subdir.path)") {
              status = "● running".green()
            }

            if let vmName = subdir.pathComponents.last {
              print("\(status) \(vmName)")
            }
          }
        }
      } catch {
        print("Error determining status of all vms: \(error)")
      }
    }
  }

  fileprivate static func vmIsRunning(atPath vmPath: String) -> Bool {
    let screenFileCount = Result { try Folder(path: "\(vmPath)/screen").files.count() }

    switch screenFileCount {
    case let .success(count) where count > 0:
      return true
    default:
      return false
    }
  }

  fileprivate func readConfigFromDisk() -> [String: String]? {
    guard let vmDirectoryPath = getVmDirectoryPath() else {
      return .none
    }

    let vmConfFile = "\(vmDirectoryPath)/vm.conf"

    guard let vmConfString = try? NSString(contentsOfFile: vmConfFile, encoding: String.Encoding.utf8.rawValue) else {
      return .none
    }

    return Self.readConfigFrom(string: vmConfString as String)
  }

  fileprivate static func readConfigFrom(string config: String) -> [String: String] {
    var configData: [String: String] = [:]

    let lines = config.components(separatedBy: "\n")

    for line in lines {
      if !line.isEmpty {
        let components = line.split(separator: "=", maxSplits: 1).map(String.init)

        if components.count == 2 {
          let key = components[0]
          let value = components[1]

          configData[key] = value
        }
      }
    }

    return configData
  }

  fileprivate static func configDataToString(data config: [String: String], macaddr: String) -> String {
    var commandArgs: [String] = []

    config.forEach { key, value in
      var string: String

      if key == "network" {
        string = "--\(key)='\(macaddr)@\(value)'"
      } else {
        string = "--\(key)='\(value)'"
      }

      commandArgs.append(string)
    }

    return commandArgs.joined(separator: " ")
  }
}
