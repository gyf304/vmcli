import Darwin
import Foundation

/// Struct used to model shell interactions.
struct Shell {
  fileprivate static let sshCommand = "ssh -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

  /// Run a shell command and capture the output as a String
  static func runShellCaptureOutput(_ cmd: String) -> String {
    let process = Process()
    let pipe = Pipe()
    var args = ["-c"]

    args.append(cmd)

    process.launchPath = "/bin/sh"
    process.arguments = args
    process.standardOutput = pipe

    process.launch()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let stringFromData = NSString(data: data, encoding: String.Encoding.utf8.rawValue)!

    return stringFromData as String
  }

  /// Run a shell command and wait for the child process spawned to end before continuing execution.
  static func runShell(_ cmd: String) -> Int32 {
    var pid: Int32 = 0
    let args = ["/bin/sh", "-c", cmd]
    let argv: [UnsafeMutablePointer<CChar>?] = args.map { $0.withCString(strdup) }

    defer { for case let arg? in argv { free(arg) } }

    if posix_spawn(&pid, argv[0], nil, nil, argv + [nil], environ) < 0 {
      print("ERROR: Unable to spawn")

      return 1
    }

    var status: Int32 = 0
    _ = waitpid(pid, &status, 0)

    return status
  }

  static func ssh(_ host: String) {
    _ = runShell("\(sshCommand) \(host)")
  }

  static func sshRunCommand(_ host: String, command: String) -> String {
    return runShellCaptureOutput("\(sshCommand) \(host) -C '\(command)'")
  }

  static func wipeScreenDeadSockets(_ path: String) {
    _ = runShellCaptureOutput("SCREENDIR='\(path)/screen' screen -wipe &>/dev/null || true")
  }

  static func attachToVMScreen(_ path: String) {
    _ = runShell("SCREENDIR=\(path)/screen screen -r")
  }

  static func arpTable() -> String {
    // This could be improved in one of several ways
    // 1. Stick with shell method and limit arp to correct interface to quickly find our vm (e.g. arp -a -i bridge100)
    // 2. import arp headers and use directly (https://stackoverflow.com/a/2189557)
    let arpCommand = """
      arp -a -i bridge100 |
      cut -d ' ' -f 2,4 |
      grep : |
      sed 's/[\\(\\)]//g' |
      sed 's/[: ]/ 0x/g' |
      xargs -L 1 printf '%s %02x%02x%02x%02x%02x%02x\n'
    """

    return runShellCaptureOutput(arpCommand)
  }

  static func vmcli(_ path: String, args: String) {
    _ = runShellCaptureOutput("SCREENDIR=\(path)/screen screen -dm sh -c \"pushd \(path) > /dev/null; vmcli \(args)\"")
  }

  static func hdiutilMakeHybrid(_ path: String) -> String {
    return runShellCaptureOutput("hdiutil makehybrid -iso -joliet -iso-volume-name cidata -joliet-volume-name cidata -o \(path)/../seed.iso \(path)")
  }
}
