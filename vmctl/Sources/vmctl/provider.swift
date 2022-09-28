import Foundation
import Tuxedo

/// The Provider protocol is an abstraction designed to allow interfacing with different OS
/// providers and specific first boot setups (via cloud-init) for each of them.
protocol Provider {
  var sshPublicKeypath: String { get set }
  var staticIpAddress: String { get set }
  var vmName: String { get set }

  init(config: ProviderConfig)

  /// Used to generate the user-data portion of cloud-init
  func generateUserData() -> String
  /// Used to generate the meta-data portion of cloud-init
  func generateMetaData() -> String
  /// Used to generate the network-config portion of cloud-init
  func generateNetworkConfig() -> String
  /// URL that points to a kernel file to be used
  func kernelURL() -> URL
  /// URL that points to an initrd file to be used
  func initrdURL() -> URL
  /// URL that points to a disk image file to be used
  func diskImageURL() -> URL
  /// Name of the concrete class that implements the Provider protocol
  func providerName() -> String
  /// Post processing closure after downloading a kernel file.
  /// Any processing must replace the file located at the given url.
  ///
  /// - Parameters:
  ///   - url: URL to the downloaded kernel file (located in a temporary location).
  ///
  func postProcessingForKernel() -> (URL) -> Void
  /// Post processing closure after downloading an initrd file.
  /// Any processing must replace the file located at the given url.
  ///
  /// - Parameters:
  ///   - url: URL to the downloaded initrd file (located in a temporary location).
  ///
  func postProcessingForInitrd() -> (URL) -> Void
  /// Post processing closure after downloading a disk image file.
  /// Any processing must replace the file located at the given url.
  ///
  /// - Parameters:
  ///   - url: URL to the downloaded disk image file (located in a temporary location).
  ///
  func postProcessingForDiskImage() -> (URL) -> Void
}

extension Provider where Self: NSObject {
  init(config: ProviderConfig) {
    self.init()
    sshPublicKeypath = config.sshPublicKeypath
    staticIpAddress = config.staticIpAddress
    vmName = config.vmName
  }

  func generateMetaData() -> String {
    return renderTemplate("meta-data")
  }

  func generateNetworkConfig() -> String {
    return renderTemplate("network-config", context: ["staticIpAddress": staticIpAddress])
  }

  func postProcessingForKernel() -> (URL) -> Void {
    return { (_: URL) in
    }
  }

  func postProcessingForInitrd() -> (URL) -> Void {
    return { (_: URL) in
    }
  }

  func postProcessingForDiskImage() -> (URL) -> Void {
    return { (_: URL) in
    }
  }

  func getCurrentUsername() -> String {
    return NSUserName()
  }

  func providerName() -> String {
    let selector = NSSelectorFromString("className")

    return perform(selector).takeRetainedValue() as! String
  }

  func sshPublicKey() -> String {
    let filemanager = FileManager.default
    let path = (sshPublicKeypath as NSString).expandingTildeInPath

    if filemanager.fileExists(atPath: path) {
      if let keyString = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) {
        return keyString as String
      }
    }

    return ""
  }

  /// Used to determine whether we are running on an x86_64 processor or arm64 processor
  func cpuArchitecture() -> String {
    var systemInfo = utsname()

    uname(&systemInfo)

    let size = Int(_SYS_NAMELEN) // is 32, but posix AND its init is 256....

    let arch = withUnsafeMutablePointer(to: &systemInfo.machine) { p in
      p.withMemoryRebound(to: CChar.self, capacity: size) { p2 in
        String(cString: p2)
      }
    }

    if arch == "x86_64" {
      return "amd64"
    }

    return arch
  }

  /// Used to render cloud-init yaml templates for a given provider.
  ///
  /// - Parameters:
  ///   - name: Name of the template to be rendered.
  ///   - context: Variable context to be used when rendering the template
  ///
  func renderTemplate(_ name: String, context: [String: Any] = [:]) -> String {
    let engine = Tuxedo()
    let templatePath = Bundle.module.url(forResource: name, withExtension: "yml", subdirectory: "templates/\(providerName())")

    if let templatePath = templatePath {
      let results = try? engine.evaluate(template: templatePath, variables: context)

      return results!
    } else {
      print("Unable to find template named \(name) in templates/\(providerName())")
      exit(1)
    }
  }
}
