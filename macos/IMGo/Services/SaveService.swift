import AppKit

/// Implements the four save modes of the previous save_files command:
/// SAVE_AS, OVERRIDE, AUTO_NEW_NAME and SAVE_TO_DIR.
enum SaveService {
  struct SaveRequest {
    let sourcePath: URL
    let format: ImageFormat
    let cacheId: String
  }

  /// Returns the ids of requests that were written successfully.
  static func save(_ requests: [SaveRequest], trigger: SaveTriggerType, newFileSuffix: String) -> [String] {
    guard !requests.isEmpty else { return [] }

    switch trigger {
    case .saveAs:
      return saveAs(requests[0])
    case .override:
      return writeAll(requests) { request in
        FinalTarget(path: request.sourcePath, override: true)
      }
    case .autoNewName:
      return writeAll(requests) { request in
        var path = applySuffix(request.sourcePath, suffix: newFileSuffix)
        path = reformExtensionIfNeeded(path, format: request.format)
        return FinalTarget(path: path, override: false)
      }
    case .saveToDir:
      return saveToDir(requests)
    }
  }

  // MARK: - Modes

  private static func saveAs(_ request: SaveRequest) -> [String] {
    let suggested = reformExtensionIfNeeded(request.sourcePath, format: request.format)

    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = suggested.lastPathComponent
    panel.directoryURL = suggested.deletingLastPathComponent()

    guard panel.runModal() == .OK, let target = panel.url else {
      return []
    }

    let wrote = write(request: request, to: target, override: true)
    return wrote ? [request.cacheId] : []
  }

  private static func saveToDir(_ requests: [SaveRequest]) -> [String] {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.message = I18n.t("save_to_dir")

    guard panel.runModal() == .OK, let directory = panel.url else {
      return []
    }

    return writeAll(requests) { request in
      let named = reformExtensionIfNeeded(request.sourcePath, format: request.format)
      let target = directory.appendingPathComponent(named.lastPathComponent)
      return FinalTarget(path: target, override: false)
    }
  }

  private struct FinalTarget {
    let path: URL
    let override: Bool
  }

  private static func writeAll(
    _ requests: [SaveRequest],
    resolve: (SaveRequest) -> FinalTarget
  ) -> [String] {
    var saved: [String] = []
    for request in requests {
      let target = resolve(request)
      let finalPath = target.override ? target.path : unoccupiedPath(nearestTo: target.path)
      if write(request: request, to: finalPath, override: target.override) {
        saved.append(request.cacheId)
      }
    }
    return saved
  }

  private static func write(request: SaveRequest, to path: URL, override: Bool) -> Bool {
    guard let data = CacheStore.read(request.cacheId) else { return false }

    if !override {
      // The path was resolved via unoccupiedPath already; re-check to stay
      // safe against races.
      if FileManager.default.fileExists(atPath: path.path) { return false }
    }

    do {
      try data.write(to: path, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Path helpers (ported from save_files.rs)

  /// Rewrites the extension when it does not match the output format
  /// (photo.jpg → photo.webp).
  static func reformExtensionIfNeeded(_ url: URL, format: ImageFormat) -> URL {
    let currentExt = url.pathExtension.lowercased()
    if let detected = ImageFormat.detect(fromExtension: currentExt), detected == format {
      return url
    }
    return (url.deletingPathExtension()).appendingPathExtension(format.fileExtension)
  }

  /// Appends a suffix to the file stem (photo.png → photo-min.png).
  static func applySuffix(_ url: URL, suffix: String) -> URL {
    guard !suffix.isEmpty else { return url }
    let stem = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension
    let dir = url.deletingLastPathComponent()
    let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
    return dir.appendingPathComponent(name)
  }

  /// Finds a path that does not collide with existing files by appending
  /// " (1)", " (2)", … to the stem (a.png → a (1).png).
  static func unoccupiedPath(nearestTo url: URL) -> URL {
    if !FileManager.default.fileExists(atPath: url.path) {
      return url
    }

    let dir = url.deletingLastPathComponent()
    let stem = url.deletingPathExtension().lastPathComponent
    let ext = url.pathExtension

    var index = 1
    while true {
      let name = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
      let candidate = dir.appendingPathComponent(name)
      if !FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }
}
