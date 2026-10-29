import Foundation

/// Schedules FFI optimize calls with the same concurrency rule as the
/// previous app: at most `max(cores - 1, 2)` encoders running at once.
/// Identical in-flight requests (same cache key) share one job.
actor OptimizeEngine {
  static let shared = OptimizeEngine()

  private let limit = max(ProcessInfo.processInfo.activeProcessorCount - 1, 2)
  private var running = 0
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var inFlight: [String: Task<OptimizeOutput, Error>] = [:]
  private let queue = DispatchQueue(label: "imgo.optimize", qos: .userInitiated)

  func optimize(
    input: Data,
    cacheKey key: String,
    outputFormat: ImageFormat?,
    options: OptimizeOptions?
  ) async throws -> OptimizeOutput {
    if let existing = inFlight[key] {
      return try await existing.value
    }

    let task = Task<OptimizeOutput, Error> {
      do {
        defer { Task { await self.finish(key: key) } }
        await acquire()
        defer { Task { await self.release() } }
        return try await withCheckedThrowingContinuation { continuation in
          queue.async {
            do {
              continuation.resume(returning: try Minifier.optimize(
                input: input,
                outputFormat: outputFormat,
                options: options
              ))
            } catch {
              continuation.resume(throwing: error)
            }
          }
        }
      }
    }

    inFlight[key] = task
    return try await task.value
  }

  private func finish(key: String) {
    inFlight[key] = nil
  }

  private func acquire() async {
    if running < limit {
      running += 1
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  private func release() {
    if waiters.isEmpty {
      running = max(running - 1, 0)
    } else {
      waiters.removeFirst().resume()
    }
  }
}
