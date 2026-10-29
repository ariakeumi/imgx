import Foundation
import CryptoKit

/// On-disk cache for optimize outputs and thumbnails, mirroring the previous
/// app's `~/Library/Caches/com.meowtec.imgo/oss/` layout (cleared on launch
/// and quit, `thumb/` subdirectory included). Source images stay where they
/// are; only generated files are cached.
enum CacheStore {
  static let root: URL = {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    return caches.appendingPathComponent("com.meowtec.imgo/oss", isDirectory: true)
  }()

  static func setup() {
    clearAll()
    try? FileManager.default.createDirectory(at: root.appendingPathComponent("thumb"), withIntermediateDirectories: true)
  }

  static func clearAll() {
    try? FileManager.default.removeItem(at: root)
  }

  static func url(for id: String) -> URL {
    root.appendingPathComponent(id)
  }

  static func write(_ data: Data, id: String) {
    let target = url(for: id)
    let directory = target.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: target, options: .atomic)
  }

  static func read(_ id: String) -> Data? {
    try? Data(contentsOf: url(for: id))
  }

  static func remove(ids: [String]) {
    for id in ids {
      try? FileManager.default.removeItem(at: url(for: id))
    }
  }
}

/// Cache keys replicate the previous app's scheme: SHA-512 of the request,
/// truncated to 16 bytes, hex-encoded.
enum CacheKey {
  static func fileId(sourceData: Data, sourcePath: String) -> String {
    var hasher = SHA512()
    hasher.update(data: sourceData)
    hasher.update(data: Data(sourcePath.utf8))
    return hex(hasher.finalize().prefix(16))
  }

  static func fileId(streaming url: URL) throws -> String {
    var hasher = SHA512()
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    while let chunk = try handle.read(upToCount: 1 << 16), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    hasher.update(data: Data(url.path.utf8))
    return hex(hasher.finalize().prefix(16))
  }

  static func resultId(
    fileId: String,
    outputFormat: ImageFormat,
    options: OptimizeOptions,
    idPrefix: String = ""
  ) -> String {
    let key = [
      "file:\(fileId)",
      "format:\(outputFormat.rawValue)",
      describe(options),
    ].joined(separator: "|")
    return idPrefix + hex(SHA512.hash(data: Data(key.utf8)).prefix(16))
  }

  static func resultCacheName(id: String, format: ImageFormat) -> String {
    "\(id).\(format.fileExtension)"
  }

  private static func describe(_ options: OptimizeOptions) -> String {
    var parts: [String] = []
    parts.append("q:\(options.quality)")
    if let indexed = options.indexed { parts.append("indexed:\(indexed)") }
    if let lossless = options.lossless { parts.append("lossless:\(lossless)") }
    if let metadata = options.preserveMetadata { parts.append("meta:\(metadata)") }
    if let fastest = options.fastest { parts.append("fastest:\(fastest)") }
    if let speed = options.speed { parts.append("speed:\(speed)") }
    if let resize = options.resize {
      parts.append("resize:\(resize.width)x\(resize.height):\(resize.type.rawValue)")
    }
    return parts.joined(separator: ",")
  }

  private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
