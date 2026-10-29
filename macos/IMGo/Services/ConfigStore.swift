import Foundation

/// Persists AppOptions to
/// `~/Library/Application Support/com.meowtec.imgo/options.json` with the
/// same schema (and atomic tmp+rename write) as the previous Tauri config.
enum ConfigStore {
  static let fileURL: URL = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("com.meowtec.imgo/options.json")
  }()

  static func load() -> AppOptions {
    guard
      let data = try? Data(contentsOf: fileURL),
      let options = try? JSONDecoder().decode(AppOptions.self, from: data)
    else {
      return AppOptions()
    }
    return options
  }

  static func save(_ options: AppOptions) {
    let directory = fileURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(options) else { return }

    let tmpURL = fileURL.appendingPathExtension("tmp")
    do {
      try data.write(to: tmpURL, options: .atomic)
      _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
    } catch {
      try? FileManager.default.removeItem(at: tmpURL)
    }
  }
}
