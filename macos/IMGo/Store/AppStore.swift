import Foundation
import Observation
import AppKit

// MARK: - TaskItem

@Observable
final class TaskItem: Identifiable {
  enum ThumbState: Equatable {
    case waiting
    case loading
    case done(String)  // cache id of the webp thumbnail
    case failed
  }

  enum ResultState: Equatable {
    case idle
    case processing(String)  // processId guard against stale completions
    case completed(Completed)
    case error(String)

    struct Completed: Equatable {
      var cacheId: String
      var format: ImageFormat
      var width: UInt32
      var height: UInt32
      var size: UInt64
      var saved: Bool
    }

    static func == (lhs: ResultState, rhs: ResultState) -> Bool {
      switch (lhs, rhs) {
      case (.idle, .idle): true
      case (.processing(let a), .processing(let b)): a == b
      case (.completed(let a), .completed(let b)): a == b
      case (.error(let a), .error(let b)): a == b
      default: false
      }
    }
  }

  let id: String
  let sourceURL: URL
  let fileName: String
  let inputFormat: ImageFormat
  let inputSize: UInt64
  var inputResolution: ImageResolution?
  var outputFormat: ImageFormat
  var options: OptimizeOptions
  var thumb: ThumbState = .waiting
  var result: ResultState = .idle

  init(
    id: String,
    sourceURL: URL,
    inputFormat: ImageFormat,
    inputSize: UInt64,
    outputFormat: ImageFormat,
    options: OptimizeOptions
  ) {
    self.id = id
    self.sourceURL = sourceURL
    self.fileName = sourceURL.lastPathComponent
    self.inputFormat = inputFormat
    self.inputSize = inputSize
    self.outputFormat = outputFormat
    self.options = options
  }

  var isProcessing: Bool {
    if case .processing = result { return true }
    return false
  }

  var completedResult: ResultState.Completed? {
    if case .completed(let completed) = result { return completed }
    return nil
  }
}

// MARK: - Store

@MainActor
@Observable
final class AppStore {
  static let shared = AppStore()

  struct AddLoading: Equatable {
    var activeIds: Set<String> = []
    var latestFileName = ""
  }

  struct Toast: Equatable, Identifiable {
    let id = UUID()
    var title: String
    var description: String
  }

  private(set) var tasks: [TaskItem] = []
  private(set) var appOptions: AppOptions
  private(set) var addLoading = AddLoading()
  private(set) var activeTaskId: String?
  private(set) var toast: Toast?
  var settingsVisible = false

  private var toastDismissTask: Task<Void, Never>?
  private let thumbnailSize: UInt32 = 640

  private init() {
    appOptions = ConfigStore.load()
  }

  var hasTasks: Bool {
    !tasks.isEmpty || !addLoading.activeIds.isEmpty
  }

  var processingCount: Int {
    tasks.filter(\.isProcessing).count
  }

  // MARK: - Import

  /// Imports image files (panel picks, drag & drop, Finder open events).
  func addURLs(_ urls: [URL]) {
    let importable = urls.filter { ImageFormat.detect(fromPath: $0.path) != nil }
    guard !importable.isEmpty else { return }

    let batchId = UUID().uuidString
    addLoading.activeIds.insert(batchId)

    Task.detached(priority: .userInitiated) { [weak self] in
      for url in importable {
        await MainActor.run {
          self?.addLoading.latestFileName = url.lastPathComponent
        }
        await self?.addImportedFile(url)
      }
      await MainActor.run {
        self?.addLoading.activeIds.remove(batchId)
      }
    }
  }

  func addFolder(_ folder: URL) {
    let batchId = UUID().uuidString
    addLoading.activeIds.insert(batchId)

    Task.detached(priority: .userInitiated) { [weak self] in
      let files = ImportService.walkFolder(folder)
      for url in files {
        await MainActor.run {
          self?.addLoading.latestFileName = url.lastPathComponent
        }
        await self?.addImportedFile(url)
      }
      await MainActor.run {
        self?.addLoading.activeIds.remove(batchId)
      }
    }
  }

  private func addImportedFile(_ url: URL) async {
    guard let format = ImageFormat.detect(fromPath: url.path) else { return }

    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? nil
    guard let fileId = try? CacheKey.fileId(streaming: url) else {
      showToast(title: I18n.t("add"), description: ImportError.unreadableFile(url).localizedDescription)
      return
    }

    await MainActor.run {
      guard !self.tasks.contains(where: { $0.id == fileId }) else { return }

      let defaults = Self.defaultOptions(inputFormat: format, appOptions: self.appOptions)
      let task = TaskItem(
        id: fileId,
        sourceURL: url,
        inputFormat: format,
        inputSize: size ?? 0,
        outputFormat: defaults.outputFormat,
        options: defaults.options
      )
      self.tasks.append(task)
      self.scheduleProcessing()
    }
  }

  // MARK: - Scheduling (port of pickRunTask + taskCluster)

  func scheduleProcessing() {
    for task in tasks {
      if task.thumb == .waiting {
        submitThumbnail(for: task)
      }
      if case .idle = task.result {
        submitOptimize(for: task)
      }
    }
  }

  private func submitThumbnail(for task: TaskItem) {
    task.thumb = .loading
    let key = CacheKey.resultId(
      fileId: task.id,
      outputFormat: .webp,
      options: OptimizeOptions(
        quality: 85,
        resize: ResizeOptions(width: thumbnailSize, height: thumbnailSize, type: .downsizeCover),
        fastest: true
      ),
      idPrefix: "thumb/"
    )

    Task.detached(priority: .userInitiated) { [weak self] in
      let output: OptimizeOutput?
      do {
        let input = try Data(contentsOf: task.sourceURL)
        output = try await OptimizeEngine.shared.optimize(
          input: input,
          cacheKey: key,
          outputFormat: .webp,
          options: OptimizeOptions(
            quality: 85,
            resize: ResizeOptions(width: self?.thumbnailSize ?? 180, height: self?.thumbnailSize ?? 180, type: .downsizeCover),
            fastest: true
          )
        )
      } catch {
        output = nil
      }

      await MainActor.run {
        guard let self else { return }
        guard let current = self.tasks.first(where: { $0.id == task.id }) else { return }
        if let output {
          let cacheId = CacheKey.resultCacheName(id: key, format: output.format)
          CacheStore.write(output.data, id: cacheId)
          current.thumb = .done(cacheId)
          if current.inputResolution == nil {
            current.inputResolution = ImageResolution(width: output.inputWidth, height: output.inputHeight)
          }
        } else {
          current.thumb = .failed
        }
      }
    }
  }

  private func submitOptimize(for task: TaskItem) {
    let processId = UUID().uuidString
    task.result = .processing(processId)

    let outputFormat = task.outputFormat
    let options = task.options
    let key = CacheKey.resultId(fileId: task.id, outputFormat: outputFormat, options: options)

    Task.detached(priority: .userInitiated) { [weak self] in
      do {
        let input = try Data(contentsOf: task.sourceURL)
        let output = try await OptimizeEngine.shared.optimize(
          input: input,
          cacheKey: key,
          outputFormat: outputFormat,
          options: options
        )

        await MainActor.run {
          guard let self else { return }
          guard
            let current = self.tasks.first(where: { $0.id == task.id }),
            case .processing(let currentProcessId) = current.result,
            currentProcessId == processId
          else { return }

          let cacheId = CacheKey.resultCacheName(id: key, format: output.format)
          CacheStore.write(output.data, id: cacheId)
          current.inputResolution = ImageResolution(width: output.inputWidth, height: output.inputHeight)
          current.result = .completed(.init(
            cacheId: cacheId,
            format: output.format,
            width: output.width,
            height: output.height,
            size: UInt64(output.data.count),
            saved: false
          ))
        }
      } catch {
        await MainActor.run {
          guard let self else { return }
          guard
            let current = self.tasks.first(where: { $0.id == task.id }),
            case .processing(let currentProcessId) = current.result,
            currentProcessId == processId
          else { return }
          current.result = .error(error.localizedDescription)
        }
      }
    }
  }

  // MARK: - Task mutations

  var canScaleAllTasks: Bool {
    !tasks.isEmpty && tasks.allSatisfy { $0.inputResolution != nil }
  }

  @discardableResult
  func applyScaleToAllTasks(_ percentage: Double) -> Bool {
    guard canScaleAllTasks else { return false }
    let sizes = tasks.compactMap { task in
      task.inputResolution.flatMap { ResizeOptions.scaled(from: $0, percentage: percentage) }
    }
    guard sizes.count == tasks.count else { return false }
    for (task, size) in zip(tasks, sizes) {
      task.options.resize = percentage == 100 ? nil : size
      task.result = .idle
    }
    scheduleProcessing()
    showToast(title: I18n.t("batch_resize"),
      description: I18n.tpl("batch_resize_description", String(tasks.count)))
    return true
  }

  func updateTaskOptions(_ taskId: String, outputFormat: ImageFormat, options: OptimizeOptions) {
    guard let task = tasks.first(where: { $0.id == taskId }) else { return }
    task.outputFormat = outputFormat
    task.options = options
    task.result = .idle
    scheduleProcessing()
  }

  /// Applies the same resize settings to every task (nil clears resize) and reruns them.
  func applyResizeToAllTasks(_ resize: ResizeOptions?) {
    guard !tasks.isEmpty else { return }
    for task in tasks {
      task.options.resize = resize
      task.result = .idle
    }
    scheduleProcessing()
    showToast(
      title: I18n.t("batch_resize"),
      description: I18n.tpl("batch_resize_description", String(tasks.count))
    )
  }

  func removeTasks(ids: [String]) {
    let idSet = Set(ids)
    let removed = tasks.filter { idSet.contains($0.id) }
    tasks.removeAll { idSet.contains($0.id) }
    clearCache(for: removed)
    if let activeTaskId, idSet.contains(activeTaskId) {
      self.activeTaskId = nil
    }
  }

  func removeAllTasks() {
    clearCache(for: tasks)
    tasks.removeAll()
    activeTaskId = nil
  }

  private func clearCache(for tasks: [TaskItem]) {
    var ids: [String] = []
    for task in tasks {
      if case .done(let thumbId) = task.thumb {
        ids.append(thumbId)
      }
      if case .completed(let completed) = task.result {
        ids.append(completed.cacheId)
      }
    }
    CacheStore.remove(ids: ids)
  }

  func setActiveTask(_ id: String?) {
    activeTaskId = id
  }

  // MARK: - App options

  func updateAppOptions(_ newOptions: AppOptions, rerunAll: Bool) {
    appOptions = newOptions
    ConfigStore.save(newOptions)

    if rerunAll {
      for task in tasks {
        let defaults = Self.defaultOptions(inputFormat: task.inputFormat, appOptions: newOptions)
        task.outputFormat = defaults.outputFormat
        task.options = defaults.options
        task.result = .idle
      }
      scheduleProcessing()
    }
  }

  /// First matching profile wins; empty inputFormats matches everything.
  static func defaultOptions(
    inputFormat: ImageFormat,
    appOptions: AppOptions
  ) -> (outputFormat: ImageFormat, options: OptimizeOptions) {
    let profile = appOptions.globalDefaultOptions.first { profile in
      profile.inputFormats.isEmpty || profile.inputFormats.contains(inputFormat)
    }

    if let profile {
      return (profile.outputFormat ?? inputFormat, profile.options)
    }
    return (inputFormat, OptimizeOptions(indexed: false, quality: 75))
  }

  // MARK: - Save

  /// Port of saveCompleted: gathers completed results, applies the skip
  /// rules, writes them out, then marks the saved ids.
  func saveCompleted(trigger: SaveTriggerType) {
    var requests: [SaveService.SaveRequest] = []
    var skippedCount = 0

    for task in tasks {
      guard let completed = task.completedResult else { continue }
      if shouldSkipBatchSave(task) {
        skippedCount += 1
        continue
      }
      requests.append(.init(
        sourcePath: task.sourceURL,
        format: completed.format,
        cacheId: completed.cacheId
      ))
    }

    if requests.isEmpty {
      if skippedCount > 0 {
        showToast(title: "", description: saveDescription(saved: 0, skipped: skippedCount))
      }
      return
    }

    let savedIds = SaveService.save(
      requests,
      trigger: trigger,
      newFileSuffix: appOptions.newFileNameSuffix
    )

    let savedIdSet = Set(savedIds)
    for task in tasks {
      guard
        var completed = task.completedResult,
        savedIdSet.contains(completed.cacheId)
      else { continue }
      completed.saved = true
      task.result = .completed(completed)
    }

    if savedIds.isEmpty {
      showToast(
        title: I18n.t("save_failed"),
        description: I18n.t("save_failed_description")
      )
    } else {
      showToast(
        title: I18n.t("save_success"),
        description: saveDescription(saved: savedIds.count, skipped: skippedCount)
      )
    }
  }

  func saveSingle(taskId: String, trigger: SaveTriggerType) {
    guard
      let task = tasks.first(where: { $0.id == taskId }),
      let completed = task.completedResult
    else { return }

    let savedIds = SaveService.save(
      [.init(sourcePath: task.sourceURL, format: completed.format, cacheId: completed.cacheId)],
      trigger: trigger,
      newFileSuffix: appOptions.newFileNameSuffix
    )

    if savedIds.contains(completed.cacheId) {
      task.result = .completed(.init(
        cacheId: completed.cacheId,
        format: completed.format,
        width: completed.width,
        height: completed.height,
        size: completed.size,
        saved: true
      ))
      showToast(
        title: I18n.t("save_success"),
        description: saveDescription(saved: 1, skipped: 0)
      )
    } else if !savedIds.isEmpty || trigger != .saveAs {
      showToast(title: I18n.t("save_failed"), description: I18n.t("save_failed_description"))
    }
    // SAVE_AS cancelled in the panel is not an error.
  }

  /// Port of shouldSkipBatchSave.
  private func shouldSkipBatchSave(_ task: TaskItem) -> Bool {
    guard let completed = task.completedResult, appOptions.skipSaveType != .none else {
      return false
    }
    if appOptions.skipSaveType == .sameFormat, task.inputFormat != completed.format {
      return false
    }
    return Double(completed.size) / Double(max(task.inputSize, 1)) > appOptions.skipSaveMinRatio
  }

  private func saveDescription(saved: Int, skipped: Int) -> String {
    let savedText = I18n.tpl("images_saved", String(saved))
    if skipped > 0 {
      return "\(savedText) · \(I18n.tpl("images_skipped", String(skipped)))"
    }
    return savedText
  }

  // MARK: - Toast

  func showToast(title: String, description: String) {
    toast = Toast(title: title, description: description)
    toastDismissTask?.cancel()
    toastDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      if !Task.isCancelled {
        self?.toast = nil
      }
    }
  }
}
