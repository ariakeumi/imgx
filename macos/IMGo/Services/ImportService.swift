import AppKit
import UniformTypeIdentifiers

enum ImportError: LocalizedError {
  case unreadableFile(URL)

  var errorDescription: String? {
    switch self {
    case .unreadableFile(let url):
      "Failed to read \(url.lastPathComponent)"
    }
  }
}

enum ImportService {
  static let supportedExtensions = [
    "png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "heif", "jxl",
  ]

  static var allowedContentTypes: [UTType] {
    var types = Set<UTType>()
    for ext in supportedExtensions {
      if let type = UTType(filenameExtension: ext) {
        types.insert(type)
      }
    }
    return Array(types)
  }

  /// Modal open panel for image files. Returns nil when cancelled.
  static func pickFiles() -> [URL]? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = allowedContentTypes
    panel.message = I18n.t("choose_images")
    guard panel.runModal() == .OK else { return nil }
    return panel.urls
  }

  /// Modal open panel for a folder. Returns nil when cancelled.
  static func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = I18n.t("select_folder")
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }

  /// Recursively lists importable images under `folder`, skipping
  /// dot-prefixed entries (mirrors the previous walkdir behavior).
  static func walkFolder(_ folder: URL) -> [URL] {
    var results: [URL] = []
    let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]

    guard
      let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: options
      )
    else {
      return []
    }

    for case let url as URL in enumerator {
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
      if isDirectory {
        if url.lastPathComponent.hasPrefix(".") {
          enumerator.skipDescendants()
        }
        continue
      }
      if ImageFormat.detect(fromPath: url.path) != nil {
        results.append(url)
      }
    }

    return results.sorted { $0.path < $1.path }
  }
}
