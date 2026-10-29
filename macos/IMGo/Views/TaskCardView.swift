import SwiftUI

struct TaskListView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    GeometryReader { geometry in
      // Fit three cards in restored windows as well as the initial window.
      let count = min(3, max(1, Int((geometry.size.width - 12) / 260)))
      let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: count)
      ScrollView {
        LazyVGrid(columns: columns, spacing: 12) {
          ForEach(store.tasks) { task in
            TaskCardView(task: task)
          }
        }
        .padding(12)
      }
    }
  }
}

struct TaskCardView: View {
  @Environment(AppStore.self) private var store
  let task: TaskItem

  @State private var quality: Double = 85
  @State private var editingQuality = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        statusIcon
        Text(task.fileName)
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(task.fileName)
        Spacer(minLength: 0)
        Menu {
          Button(I18n.t("save_new_file")) {
            store.saveSingle(taskId: task.id, trigger: .autoNewName)
          }
          Button(I18n.t("save_as")) {
            store.saveSingle(taskId: task.id, trigger: .saveAs)
          }
          Divider()
          Button(I18n.t("save_override")) {
            store.saveSingle(taskId: task.id, trigger: .override)
          }
        } label: {
          Image(systemName: task.completedResult?.saved == true
            ? "checkmark.circle.fill" : "square.and.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(task.completedResult == nil)
        .help(I18n.t("save"))

        Button {
          store.removeTasks(ids: [task.id])
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help(I18n.t("delete_task"))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)

      Button {
        store.setActiveTask(task.id)
      } label: {
        ThumbView(state: task.thumb)
          .frame(height: 150)
          .frame(maxWidth: .infinity)
          .clipped()
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(task.fileName)

      Divider()

      HStack(spacing: 8) {
        Text(I18n.t("quality"))
          .font(.callout)
        Slider(value: $quality, in: 0...100, step: 1) { editing in
          editingQuality = editing
          if !editing { applyQuality() }
        }
        .accessibilityLabel(I18n.t("quality"))
        .disabled(task.options.lossless == true)
        Text(task.options.lossless == true ? I18n.t("lossless") : "\(Int(quality))%")
          .font(.callout.monospacedDigit())
          .frame(minWidth: 42, alignment: .trailing)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)

      Divider()

      HStack(spacing: 8) {
        Picker(I18n.t("output_format"), selection: Binding(
          get: { task.outputFormat },
          set: { format in
            var options = task.options
            options.quality = UInt8(quality)
            store.updateTaskOptions(task.id, outputFormat: format, options: options)
          }
        )) {
          ForEach(outputFormats) { format in
            Text(format.displayName).tag(format)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .frame(width: 78)
        Spacer(minLength: 0)
        resultSummary
      }
      .font(.caption.monospacedDigit())
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
    }
    .background(.background, in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.quaternary)
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
    .onAppear { quality = Double(task.options.quality) }
    .onChange(of: task.options.quality) { _, value in
      if !editingQuality { quality = Double(value) }
    }
    .onChange(of: quality) { _, _ in
      if !editingQuality { applyQuality() }
    }
  }

  private var outputFormats: [ImageFormat] {
    ImageFormat.popular.contains(task.outputFormat)
      ? ImageFormat.popular : [task.outputFormat] + ImageFormat.popular
  }

  private func applyQuality() {
    let value = UInt8(quality)
    guard task.options.quality != value else { return }
    var options = task.options
    options.quality = value
    store.updateTaskOptions(task.id, outputFormat: task.outputFormat, options: options)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch task.result {
    case .idle:
      Image(systemName: "clock").foregroundStyle(.secondary)
        .help(I18n.t("waiting"))
    case .processing:
      ProgressView().controlSize(.small)
        .help(I18n.t("processing"))
    case .error(let message):
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        .help(message)
    case .completed:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        .help(I18n.t("completed"))
    }
  }

  @ViewBuilder
  private var resultSummary: some View {
    if let result = task.completedResult {
      let ratio = task.inputSize == 0 ? 1 : Double(result.size) / Double(task.inputSize)
      let percent = (ratio - 1) * 100
      VStack(alignment: .trailing, spacing: 2) {
        Text("\(SizeFormatter.format(result.size)) / \(SizeFormatter.format(task.inputSize))")
          .font(.caption2)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(String(format: "%+.1f%%", percent))
          .foregroundStyle(ratio < 1 ? Color.green : Color.orange)
      }
    } else {
      Text(I18n.t(task.isProcessing ? "processing" : task.resultIsError ? "image_encoding_failed" : "waiting"))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

private extension TaskItem {
  var resultIsError: Bool {
    if case .error = result { return true }
    return false
  }
}

// MARK: - Thumbnail

private struct ThumbView: View {
  let state: TaskItem.ThumbState

  @State private var image: NSImage?

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.quinary)

      switch state {
      case .waiting:
        EmptyView()
      case .loading:
        ProgressView()
          .controlSize(.small)
      case .failed:
        Image(systemName: "photo")
          .foregroundStyle(.tertiary)
      case .done:
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
        } else {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
    .task(id: thumbKey) {
      loadThumbnail()
    }
  }

  private var thumbKey: String {
    if case .done(let id) = state { return id }
    return "pending"
  }

  private func loadThumbnail() {
    guard case .done(let cacheId) = state else {
      image = nil
      return
    }
    image = NSImage(contentsOf: CacheStore.url(for: cacheId))
  }
}
