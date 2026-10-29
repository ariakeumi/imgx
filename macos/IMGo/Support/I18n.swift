import Foundation

/// Locale text loader with the same fallback chain as the previous app:
/// full locale (zh-CN) → primary language (zh) → en → key itself.
final class I18n {
  static let shared = I18n()

  private var textMaps: [[String: String]] = []
  private(set) var locale: String = "en"

  private init() {
    setLocale(Self.preferredIdentifier())
  }

  func setLocale(_ identifier: String) {
    locale = identifier
    var seen = Set<String>()
    var maps: [[String: String]] = []
    for code in Self.candidateCodes(for: identifier) where seen.insert(code).inserted {
      if let map = Self.load(code: code) {
        maps.append(map)
      }
    }
    textMaps = maps
  }

  /// Locale.current reports the app's launch language, which macOS pins to the
  /// development region when the bundle declares no matching localization, so
  /// resolve the locale from the user's actual language preferences instead.
  private static func preferredIdentifier() -> String {
    let preferred = UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []
    return preferred.first { identifier in
      candidateCodes(for: identifier).contains { load(code: $0) != nil }
    } ?? Locale.current.identifier
  }

  /// Full locale (zh-Hans-CN → zh_Hans_CN) → primary language (zh) → en.
  private static func candidateCodes(for identifier: String) -> [String] {
    let normalized = identifier.replacingOccurrences(of: "-", with: "_")
    var codes = [normalized]
    if let language = normalized.split(separator: "_").first, language != normalized {
      codes.append(String(language))
    }
    codes.append("en")
    return codes
  }

  private static func load(code: String) -> [String: String]? {
    // Prefer the i18n/ subdirectory; fall back to the bundle root in case
    // the resources were copied flat.
    let url = Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "i18n")
      ?? Bundle.main.url(forResource: code, withExtension: "json")
    guard
      let url,
      let data = try? Data(contentsOf: url)
    else { return nil }
    return (try? JSONDecoder().decode([String: String].self, from: data))
  }

  static func t(_ key: String) -> String {
    shared.text(key)
  }

  static func tpl(_ key: String, _ args: String...) -> String {
    var text = shared.text(key)
    for (index, arg) in args.enumerated() {
      text = text.replacingOccurrences(of: "{\(index)}", with: arg)
    }
    return text
  }

  func text(_ key: String) -> String {
    for map in textMaps {
      if let value = map[key] {
        return value
      }
    }
    return key
  }
}
