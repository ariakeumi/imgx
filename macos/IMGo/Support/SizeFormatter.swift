import Foundation

/// Byte formatter matching the previous app: 1024-based, at most two
/// decimals without trailing zeros, unit glued to the number ("1.5MB").
enum SizeFormatter {
  static func format(_ bytes: UInt64) -> String {
    format(Double(bytes))
  }

  static func format(_ bytes: Int) -> String {
    format(Double(bytes))
  }

  static func format(_ bytes: Double) -> String {
    let k = 1024.0
    let number: Double
    let unit: String

    if bytes < 1000 {
      number = bytes
      unit = "B"
    } else if bytes < 1000 * k {
      number = trim(bytes / k)
      unit = "KB"
    } else {
      number = trim(bytes / k / k)
      unit = "MB"
    }

    if unit == "B" {
      return "\(Int(number))B"
    }
    return "\(number)\(unit)"
  }

  private static func trim(_ value: Double) -> Double {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() {
      return rounded.rounded()
    }
    return rounded
  }
}
