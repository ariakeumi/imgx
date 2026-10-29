import Foundation
import CMinifier

enum MinifierError: LocalizedError {
  case ffi(status: Int32, message: String)

  var errorDescription: String? {
    switch self {
    case .ffi(_, let message):
      message
    }
  }
}

struct OptimizeOutput {
  let data: Data
  let format: ImageFormat
  let width: UInt32
  let height: UInt32
  let inputWidth: UInt32
  let inputHeight: UInt32
}

/// Thin Swift wrapper over the imgo_minifier C ABI. Blocking; call from a
/// background queue (OptimizeEngine does).
enum Minifier {
  static func optimize(
    input: Data,
    outputFormat: ImageFormat?,
    options: OptimizeOptions?
  ) throws -> OptimizeOutput {
    guard !input.isEmpty else {
      throw MinifierError.ffi(status: 1, message: "empty input")
    }

    let request = FFIRequest(outputFormat: outputFormat, options: options)
    let requestString = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? "{}"

    var result = imgo_result()
    let status = requestString.withCString { requestPtr in
      input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
          return imgo_optimize(nil, 0, requestPtr, &result)
        }
        return imgo_optimize(base, input.count, requestPtr, &result)
      }
    }

    guard status == 0 else {
      let message = resultOfLastError()
      throw MinifierError.ffi(status: status, message: message)
    }

    defer { imgo_result_free(&result) }

    let data = Data(bytes: result.data, count: result.len)
    let metaString = String(cString: result.meta_json)
    let meta: FFIMeta
    do {
      meta = try JSONDecoder().decode(FFIMeta.self, from: Data(metaString.utf8))
    } catch {
      throw MinifierError.ffi(status: status, message: "bad result metadata: \(metaString)")
    }

    return OptimizeOutput(
      data: data,
      format: meta.format,
      width: meta.width,
      height: meta.height,
      inputWidth: meta.inputWidth,
      inputHeight: meta.inputHeight
    )
  }

  private static func resultOfLastError() -> String {
    guard let ptr = imgo_last_error() else { return "unknown error" }
    return String(cString: ptr)
  }
}
