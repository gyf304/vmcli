import ArgumentParser
import Darwin
import Foundation

struct VMCTL: ParsableCommand {
  static let configuration = CommandConfiguration(
    subcommands: [
      Create.self,
      List.self,
      Start.self,
      Stop.self,
      Ssh.self,
      Attach.self,
      IP.self,
    ]
  )

  mutating func run() throws {
    print("Hello, world!")
  }

  struct Create: ParsableCommand {
    func run() {
      print("creating new vm configuration")
    }
  }

  struct List: ParsableCommand {
    func run() {
      print("listing out vms")
    }
  }

  struct Start: ParsableCommand {
    @Argument(help: "VM to start") var vm_name: String

    func run() {
      print("starting vm")
    }
  }

  struct Stop: ParsableCommand {
    @Argument(help: "VM to stop") var vm_name: String

    func run() {
      print("stopping vm")
    }
  }

  struct Ssh: ParsableCommand {
    @Argument(help: "VM to ssh into") var vm_name: String

    func run() {
      print("ssh'ing into vm")
    }
  }

  struct Attach: ParsableCommand {
    func run() {
      print("attaching to vm")
    }
  }

  struct IP: ParsableCommand {
    @Argument(help: "VM to get ip for") var vm_name: String

    func run() {
      let vm = VM(name: vm_name)

      if let ip = vm.get_ip() {
        print(ip)
      }
    }
  }
}

VMCTL.main()
