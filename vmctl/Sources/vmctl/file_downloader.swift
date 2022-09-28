import Foundation

enum FileLoaderError: Error {
  case url
  case server
  case decoding
  case filesystem
}

enum FileLoader {
  static func download(url: URL, toFile file: URL) -> Result<URL, FileLoaderError> {
    var result: Result<URL, FileLoaderError>!

    let semaphore = DispatchSemaphore(value: 0)

    URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
      guard let tempURL = tempURL else {
        result = .failure(.url)
        return
      }

      do {
        if FileManager.default.fileExists(atPath: file.path) {
          try FileManager.default.removeItem(at: file)
        }

        try FileManager.default.copyItem(
          at: tempURL,
          to: file
        )
      } catch {
        result = .failure(.filesystem)
      }

      result = .success(file)

      semaphore.signal()
    }.resume()

    _ = semaphore.wait(wallTimeout: .distantFuture)

    return result
  }

  static func loadData(url: URL, withCachePrefix cachePrefix: String, postProcessing: (URL) -> Void) -> Result<URL, FileLoaderError> {
    print("Downloading file: \(url)")

    let cachedFile = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "\(cachePrefix).\(url.lastPathComponent)",
        isDirectory: false
      )

    if FileManager.default.fileExists(atPath: cachedFile.path) {
      return .success(cachedFile)
    }

    let file_url = download(url: url, toFile: cachedFile)

    postProcessing(cachedFile)

    return file_url
  }
}
