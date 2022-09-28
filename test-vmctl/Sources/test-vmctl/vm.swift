import Foundation

struct VM {
  var name: String

  func get_ip() -> String? {
    if let vmctldir = ProcessInfo.processInfo.environment["VMCTLDIR"] {
      let ip_file_path = "\(vmctldir)/\(name)/1.ipaddr"

      if let ip_address = try? NSString(contentsOfFile: ip_file_path, encoding: String.Encoding.utf8.rawValue) {
        return ip_address as String
      } else {
        let macaddr_file_path = "\(vmctldir)/\(name)/0.macaddr"

        if let macaddr = try? NSString(contentsOfFile: macaddr_file_path, encoding: String.Encoding.utf8.rawValue) {
          let arp_command = """
            arp -a |
            cut -d ' ' -f 2,4 |
            grep : |
            sed 's/[\\(\\)]//g' |
            sed 's/[: ]/ 0x/g' |
            xargs -L 1 printf '%s %02x%02x%02x%02x%02x%02x\n'
          """

          let output: String = Shell.run_shell_capture_output(arp_command)

          let pattern = "(.*)\\s\(macaddr)"
          let regex = try? NSRegularExpression(
            pattern: pattern,
            options: .caseInsensitive
          )

          if let match = regex?.firstMatch(in: output, options: [], range: NSRange(location: 0, length: output.utf8.count)) {
            if let ip_range = Range(match.range(at: 1), in: output) {
              let ip_address = output[ip_range]

              return String(ip_address)
            }
          }
        }
      }
    }

    return Optional.none
  }
}
