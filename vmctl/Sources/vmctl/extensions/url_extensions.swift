import Foundation

extension URL {
  func subDirectories() throws -> [URL] {
    guard hasDirectoryPath else { return [] }
    return try FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter(\.hasDirectoryPath)
  }
}
