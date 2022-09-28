import Foundation

struct ProviderConfig {
  var staticIpAddress: String
  var sshPublicKeypath: String
  var vmName: String
}

struct Config {
  var vmName: String
  var numberOfCpus: UInt
  var memory: UInt
  var provider: String
  var staticIpAddress: String?
  var sshPublicKeypath: String
  let fileManager: FileManager = .default

  public func outputConfig() {
    guard let vmctldir = ProcessInfo.processInfo.environment["VMCTLDIR"] else {
      print("ERROR: You must export VMCTLDIR before creating a vm.")
      exit(1)
    }

    let vmPath = "\(vmctldir)/\(vmName)"
    let isoPath = "\(vmPath)/iso_folder"
    let vmConfPath = "\(vmPath)/vm.conf"
    let macAddrPath = "\(vmPath)/0.macaddr"

    createDirectory(path: vmPath)
    createDirectory(path: isoPath)

    writeFile(path: vmConfPath, contents: generateVmConf())
    writeFile(path: macAddrPath, contents: "\(macaddr: generateMacAddress(), separator: "")", overwrite: false)

    generateProviderFiles(path: vmPath)
  }

  private func generateMacAddress() -> [UInt8] {
    var buffer: [UInt8] = []

    for _ in 0 ..< 6 {
      buffer.append(UInt8.random(in: 0 ... UInt8.max))
    }

    // ensuring we have a valid mac address for our vm
    // make sure bit 0 (broadcast) of first byte is not set,
    // and bit 1 (local) is set.
    // i.e. via bitwise AND with 254 and bitwise OR with 2.
    buffer[0] = (buffer[0] & 254 | 2)

    return buffer
  }

  private func createDirectory(path: String) {
    var isDirectory: ObjCBool = true

    if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
      let url = URL(fileURLWithPath: path)

      do {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
      } catch {
        print("Error during directory creation: \(error)")
      }
    }
  }

  private func writeFile(path: String, contents: String, overwrite: Bool = true) {
    if fileManager.fileExists(atPath: path), !overwrite {
      return
    }

    if fileManager.fileExists(atPath: path) {
      let url = URL(fileURLWithPath: path)
      try? fileManager.removeItem(at: url)
    }

    let data = contents.data(using: String.Encoding.utf8)

    fileManager.createFile(atPath: path, contents: data)
  }

  private func removeFile(_ path: String) {
    if fileManager.fileExists(atPath: path) {
      let url = URL(fileURLWithPath: path)
      try? fileManager.removeItem(at: url)
    }
  }

  private func generateVmConf() -> String {
    let vmConfContents = """
    kernel=vmlinux
    initrd=initrd
    cmdline=console=hvc0 irqfixup root=/dev/vda
    cpu-count=\(numberOfCpus)
    memory-size=\(memory)
    disk=disk.img
    cdrom=seed.iso
    network=nat
    """

    return vmConfContents
  }

  private func generateProviderFiles(path: String) {
    let providerConfig = ProviderConfig(staticIpAddress: staticIpAddress ?? "", sshPublicKeypath: sshPublicKeypath, vmName: vmName)

    if let provider = ProviderFactory.providerFromString(classString: provider, config: providerConfig) {
      let metaDataPath = "\(path)/iso_folder/meta-data"
      let metaDataString = provider.generateMetaData()

      let userDataPath = "\(path)/iso_folder/user-data"
      let userDataString = provider.generateUserData()

      let networkDataPath = "\(path)/iso_folder/network-config"
      let networkDataString = provider.generateNetworkConfig()

      downloadFilesAndProcess(provider, path: path)

      writeFile(path: metaDataPath, contents: metaDataString)
      writeFile(path: userDataPath, contents: userDataString)
      writeFile(path: networkDataPath, contents: networkDataString)

      removeFile("\(path)/seed.iso")

      let result = Shell.hdiutilMakeHybrid("\(path)/iso_folder")

      print(result)
    } else {
      print("Provider with name \(provider) does not exist. Please check your spelling and try again.")
    }
  }

  private func downloadFilesAndProcess(_ provider: Provider, path: String) {
    let kernelResult = FileLoader.loadData(url: provider.kernelURL(), withCachePrefix: provider.providerName(), postProcessing: provider.postProcessingForKernel())
    let initrdResult = FileLoader.loadData(url: provider.initrdURL(), withCachePrefix: provider.providerName(), postProcessing: provider.postProcessingForInitrd())
    let diskImageResult = FileLoader.loadData(url: provider.diskImageURL(), withCachePrefix: provider.providerName(), postProcessing: provider.postProcessingForDiskImage())

    do {
      let kernelFileURL = try kernelResult.get()
      try FileManager.default.moveItem(at: kernelFileURL, to: URL(fileURLWithPath: "\(path)/vmlinux"))

      let initrdFileURL = try initrdResult.get()
      try FileManager.default.moveItem(at: initrdFileURL, to: URL(fileURLWithPath: "\(path)/initrd"))

      let diskImageFileURL = try diskImageResult.get()
      try FileManager.default.moveItem(at: diskImageFileURL, to: URL(fileURLWithPath: "\(path)/disk.img"))

    } catch {
      print("Error during download/post processing provider files: \(error)")
    }
  }
}
