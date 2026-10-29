import Foundation

// MARK: - ImageFormat
// Raw values mirror the serde contract of imgo_shared::types (UPPERCASE).

enum ImageFormat: String, Codable, CaseIterable, Identifiable, Hashable {
  case png = "PNG"
  case jpeg = "JPEG"
  case gif = "GIF"
  case webp = "WEBP"
  case pnm = "PNM"
  case tiff = "TIFF"
  case tga = "TGA"
  case dds = "DDS"
  case bmp = "BMP"
  case ico = "ICO"
  case hdr = "HDR"
  case openexr = "OPENEXR"
  case farbfeld = "FARBFELD"
  case avif = "AVIF"
  case qoi = "QOI"
  case heic = "HEIC"
  case jxl = "JXL"

  var id: String { rawValue }

  /// Matches imgo_shared::ImageFormat::extensions_str (first extension).
  var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .gif: "gif"
    case .webp: "webp"
    case .pnm: "pbm"
    case .tiff: "tif"
    case .tga: "tga"
    case .dds: "dds"
    case .bmp: "bmp"
    case .ico: "ico"
    case .hdr: "hdr"
    case .openexr: "exr"
    case .farbfeld: "ff"
    case .avif: "avif"
    case .qoi: "qoi"
    case .heic: "heic"
    case .jxl: "jxl"
    }
  }

  /// Matches FILE_FORMAT_DISPLAY in the previous web UI.
  var displayName: String {
    switch self {
    case .pnm: "PBM"
    case .openexr: "EXR"
    case .farbfeld: "FF"
    default: rawValue
    }
  }

  var supportsLossless: Bool {
    switch self {
    case .png, .webp, .avif, .heic, .jxl: true
    default: false
    }
  }

  /// Input formats offered in pickers / conversion profiles.
  static let popular: [ImageFormat] = [.jpeg, .png, .gif, .webp, .avif, .heic, .jxl]

  /// Matches ImageFormat::detect_from_extension.
  static func detect(fromExtension ext: String) -> ImageFormat? {
    switch ext.lowercased() {
    case "heic", "heif": .heic
    case "jxl": .jxl
    case "png": .png
    case "jpg", "jpeg": .jpeg
    case "gif": .gif
    case "webp": .webp
    case "pbm", "pgm", "ppm": .pnm
    case "tif", "tiff": .tiff
    case "tga": .tga
    case "dds": .dds
    case "bmp": .bmp
    case "ico": .ico
    case "hdr": .hdr
    case "exr": .openexr
    case "ff", "farbfeld": .farbfeld
    case "avif": .avif
    case "qoi": .qoi
    default: nil
    }
  }

  static func detect(fromPath path: String) -> ImageFormat? {
    (path as NSString).pathExtension.isEmpty ? nil : detect(fromExtension: (path as NSString).pathExtension)
  }
}

// MARK: - Optimize options (serde: snake_case keys, UPPERCASE enums)

enum ResizeType: String, Codable, CaseIterable, Identifiable {
  case exact = "EXACT"
  case downsizeContain = "DOWNSIZE_CONTAIN"
  case downsizeCover = "DOWNSIZE_COVER"

  var id: String { rawValue }
}

struct ResizeOptions: Codable, Equatable {
  var width: UInt32
  var height: UInt32
  var type: ResizeType

  static func scaled(from original: ImageResolution, percentage: Double) -> ResizeOptions? {
    guard percentage.isFinite, (1...400).contains(percentage),
      original.width > 0, original.height > 0 else { return nil }
    let width = max(1, (Double(original.width) * percentage / 100).rounded())
    let height = max(1, (Double(original.height) * percentage / 100).rounded())
    guard width <= Double(UInt32.max), height <= Double(UInt32.max) else { return nil }
    return ResizeOptions(width: UInt32(width), height: UInt32(height), type: .exact)
  }

  enum CodingKeys: String, CodingKey {
    case width, height, type
  }
}

struct OptimizeOptions: Codable, Equatable {
  var indexed: Bool?
  var quality: UInt8
  var lossless: Bool?
  var preserveMetadata: Bool?
  var resize: ResizeOptions?
  var speed: UInt8?
  var fastest: Bool?

  init(
    indexed: Bool? = nil,
    quality: UInt8 = 85,
    lossless: Bool? = nil,
    preserveMetadata: Bool? = nil,
    resize: ResizeOptions? = nil,
    speed: UInt8? = nil,
    fastest: Bool? = nil
  ) {
    self.indexed = indexed
    self.quality = quality
    self.lossless = lossless
    self.preserveMetadata = preserveMetadata
    self.resize = resize
    self.speed = speed
    self.fastest = fastest
  }

  enum CodingKeys: String, CodingKey {
    case indexed, quality, lossless
    case preserveMetadata = "preserve_metadata"
    case resize, speed, fastest
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(indexed, forKey: .indexed)
    try container.encode(quality, forKey: .quality)
    try container.encodeIfPresent(lossless, forKey: .lossless)
    try container.encodeIfPresent(preserveMetadata, forKey: .preserveMetadata)
    try container.encodeIfPresent(resize, forKey: .resize)
    try container.encodeIfPresent(speed, forKey: .speed)
    try container.encodeIfPresent(fastest, forKey: .fastest)
  }
}

// MARK: - FFI request / response envelopes

struct FFIRequest: Codable {
  var outputFormat: ImageFormat?
  var options: OptimizeOptions?

  enum CodingKeys: String, CodingKey {
    case outputFormat = "output_format"
    case options
  }
}

struct FFIMeta: Codable {
  var format: ImageFormat
  var width: UInt32
  var height: UInt32
  var inputWidth: UInt32
  var inputHeight: UInt32
}

// MARK: - App options (serde: camelCase container, snake nested options)

enum AppTheme: String, Codable, CaseIterable, Identifiable {
  case light, dark, system
  var id: String { rawValue }
}

enum SkipSaveType: String, Codable, CaseIterable, Identifiable {
  case none = "NONE"
  case sameFormat = "SAME_FORMAT"
  case all = "ALL"
  var id: String { rawValue }
}

struct GlobalDefaultOptions: Codable, Equatable, Identifiable {
  var id = UUID()
  /// Empty list means "all input formats".
  var inputFormats: [ImageFormat]
  /// nil keeps the input format.
  var outputFormat: ImageFormat?
  var options: OptimizeOptions

  enum CodingKeys: String, CodingKey {
    case inputFormats, outputFormat, options
  }

  static func == (lhs: GlobalDefaultOptions, rhs: GlobalDefaultOptions) -> Bool {
    lhs.id == rhs.id
  }
}

struct AppOptions: Equatable {
  var skipSaveType: SkipSaveType = .none
  var skipSaveMinRatio: Double = 1.0
  var newFileNameSuffix: String = ""
  var globalDefaultOptions: [GlobalDefaultOptions] = [
    GlobalDefaultOptions(inputFormats: [], outputFormat: .webp, options: OptimizeOptions(indexed: false, quality: 70))
  ]
  var appTheme: AppTheme = .light
}

// AppOptions is decoded leniently: any missing field falls back to the same
// defaults the Rust side applies via #[serde(default)].
extension AppOptions: Decodable {
  enum CodingKeys: String, CodingKey {
    case skipSaveType, skipSaveMinRatio, newFileNameSuffix, globalDefaultOptions, appTheme
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init()
    skipSaveType = try c.decodeIfPresent(SkipSaveType.self, forKey: .skipSaveType) ?? skipSaveType
    skipSaveMinRatio = try c.decodeIfPresent(Double.self, forKey: .skipSaveMinRatio) ?? skipSaveMinRatio
    newFileNameSuffix = try c.decodeIfPresent(String.self, forKey: .newFileNameSuffix) ?? newFileNameSuffix
    globalDefaultOptions = try c.decodeIfPresent([GlobalDefaultOptions].self, forKey: .globalDefaultOptions) ?? globalDefaultOptions
    appTheme = try c.decodeIfPresent(AppTheme.self, forKey: .appTheme) ?? appTheme
  }
}

extension AppOptions: Encodable {
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(skipSaveType, forKey: .skipSaveType)
    try c.encode(skipSaveMinRatio, forKey: .skipSaveMinRatio)
    try c.encode(newFileNameSuffix, forKey: .newFileNameSuffix)
    try c.encode(globalDefaultOptions, forKey: .globalDefaultOptions)
    try c.encode(appTheme, forKey: .appTheme)
  }
}

// MARK: - Save triggers

enum SaveTriggerType: String {
  case saveAs = "SAVE_AS"
  case autoNewName = "AUTO_NEW_NAME"
  case override = "OVERRIDE"
  case saveToDir = "SAVE_TO_DIR"
}

// MARK: - Resolution

struct ImageResolution: Equatable {
  var width: UInt32
  var height: UInt32
}
