import Darwin
import Foundation

struct Shell {
  static func run_shell_capture_output(_ cmd: String) -> String {
    let task = Process()
    let outPipe = Pipe()
    var args = ["-c"]
    args.append(cmd)

    task.launchPath = "/bin/sh"
    task.arguments = args
    task.standardOutput = outPipe

    task.launch()

    let fileHandle = outPipe.fileHandleForReading
    let data = fileHandle.readDataToEndOfFile()
    let stringFromData = NSString(data: data, encoding: String.Encoding.utf8.rawValue)!

    task.waitUntilExit()

    return stringFromData as String
  }

  static func run_shell(_ cmd: String) -> Int32 {
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
}
