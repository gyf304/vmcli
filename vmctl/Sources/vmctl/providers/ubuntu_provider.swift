import DataCompression
import Foundation
import Tuxedo

@objc(UbuntuProvider) class UbuntuProvider: NSObject, Provider {
  var sshPublicKeypath: String = ""
  var staticIpAddress: String = ""
  var vmName: String = ""

  func kernelURL() -> URL {
    let arch = cpuArchitecture()

    let urlString = "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-\(arch)-vmlinuz-generic"

    return URL(string: urlString)!
  }

  func initrdURL() -> URL {
    let arch = cpuArchitecture()

    let urlString = "https://cloud-images.ubuntu.com/releases/focal/release/unpacked/ubuntu-20.04-server-cloudimg-\(arch)-initrd-generic"

    return URL(string: urlString)!
  }

  func diskImageURL() -> URL {
    let arch = cpuArchitecture()

    let urlString = "https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-\(arch).tar.gz"

    return URL(string: urlString)!
  }

  func postProcessingForKernel() -> (URL) -> Void {
    return { (url: URL) in
      do {
        if self.cpuArchitecture() == "arm64" {
          let data = try Data(contentsOf: url)
          let decompressedData = data.gunzip()
          try decompressedData?.write(to: url)
        }
      } catch {
        print("Post processing kernel data error: \(error)")
      }
    }
  }

  func postProcessingForDiskImage() -> (URL) -> Void {
    return { (url: URL) in
      do {
        let arch = self.cpuArchitecture()
        let data = try Data(contentsOf: url)
        let decompressedData = data.gunzip()
        let expandedDirectory = url.deletingLastPathComponent().appendingPathComponent("disk-image-directory")

        try decompressedData?.write(to: url)
        try FileManager.default.extractTar(at: url, to: expandedDirectory)

        _ = try FileManager.default.replaceItemAt(url, withItemAt: expandedDirectory.appendingPathComponent("focal-server-cloudimg-\(arch).img"))
      } catch {
        print("Post processing disk image data error: \(error)")
      }
    }
  }

  func generateUserData() -> String {
    let sshPublicKey = sshPublicKey()

    return renderTemplate(
      "user-data",
      context: [
        "username": getCurrentUsername(),
        "sshPublicKey": sshPublicKey,
      ]
    )
  }
}
