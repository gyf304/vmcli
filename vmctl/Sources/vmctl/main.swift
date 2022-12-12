import ArgumentParser
import Foundation

struct VMCTL: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "A command line tool for managing virtual machines.",
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

  mutating func run() {
    print(Self.helpMessage())
  }

  struct Create: ParsableCommand {
    @Argument(help: "VM to create") var vmName: String

    @Option(name: [.customShort("p"), .customLong("provider")], help: "Name of provider to use for new vm") var provider: String = "UbuntuProvider"
    @Option(name: [.customShort("c"), .customLong("numberOfCpus")], help: "Number of cpus for new vm") var numberOfCpus: UInt = 1
    @Option(name: [.customShort("m"), .customLong("memory")], help: "Memory for new vm") var memory: UInt = 1024
    @Option(name: [.customShort("i"), .customLong("staticIpAddress")], help: "Use static ip address with new vm") var staticIpAddress: String?
    @Option(name: [.customShort("s"), .customLong("sshPublicKeypath")], help: "Path to public ssh key") var sshPublicKeypath: String = "~/.ssh/id_rsa.pub"

    func run() {
      let config = Config(
        vmName: vmName,
        numberOfCpus: numberOfCpus,
        memory: memory,
        provider: provider,
        staticIpAddress: staticIpAddress,
        sshPublicKeypath: sshPublicKeypath
      )

      config.outputConfig()

      print("Created vm named \(vmName)")
    }
  }

  struct List: ParsableCommand {
    func run() {
      VM.printListOfVms()
    }
  }

  struct Start: ParsableCommand {
    @Argument(help: "VM to start") var vmName: String

    func run() {
      let vm = VM(name: vmName)

      vm.start()
    }
  }

  struct Stop: ParsableCommand {
    @Argument(help: "VM to stop") var vmName: String

    func run() {
      let vm = VM(name: vmName)

      vm.stop()
    }
  }

  struct Ssh: ParsableCommand {
    @Argument(help: "VM to ssh into") var vmName: String

    func run() {
      let vm = VM(name: vmName)

      vm.ssh()
    }
  }

  struct Attach: ParsableCommand {
    @Argument(help: "VM to attach to") var vmName: String

    func run() {
      let vm = VM(name: vmName)

      vm.attach()
    }
  }

  struct IP: ParsableCommand {
    @Argument(help: "VM to get ip for") var vmName: String

    func run() {
      let vm = VM(name: vmName)

      if let ip = vm.getIp() {
        print(ip)
      } else {
        print("could not retrieve ip")
      }
    }
  }
}

VMCTL.main()
