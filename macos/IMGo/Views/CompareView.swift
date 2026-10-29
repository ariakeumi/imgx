import SwiftUI

struct CompareView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  let task: TaskItem

  @State private var splitFraction: CGFloat = 0.5
  @State private var zoom: CGFloat = 1
  @State private var panOffset: CGSize = .zero
  @State private var panAnchor: CGSize = .zero
  @State private var inputImage: NSImage?
  @State private var outputImage: NSImage?

  private var outputCacheId: String? {
    task.completedResult?.cacheId
  }

  var body: some View {
    VStack(spacing: 0) {
      topBar
      Divider()
      HStack(spacing: 0) {
        compareCanvas
        Divider()
        TaskOptionsPanel(task: task)
          .frame(width: 280)
      }
    }
    .frame(minWidth: 760, idealWidth: 980, minHeight: 520, idealHeight: 660)
    .task(id: task.id) {
      inputImage = NSImage(contentsOf: task.sourceURL)
    }
    .task(id: outputCacheId) {
      if let outputCacheId {
        outputImage = NSImage(contentsOf: CacheStore.url(for: outputCacheId))
      } else {
        outputImage = nil
      }
    }
  }

  // MARK: - Top bar

  private var topBar: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(task.fileName)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
        statsLine
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if task.completedResult != nil {
        Button(I18n.t("save_as")) {
          store.saveSingle(taskId: task.id, trigger: .saveAs)
        }
        Button(I18n.t("save")) {
          store.saveSingle(taskId: task.id, trigger: .override)
        }
      }

      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.borderless)
      .help(I18n.t("close"))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var statsLine: some View {
    if let completed = task.completedResult {
      let ratio = task.inputSize == 0 ? 1.0 : Double(completed.size) / Double(task.inputSize)

      HStack(spacing: 6) {
        Text("\(I18n.t("before_optimized")) \(SizeFormatter.format(task.inputSize))")
        Image(systemName: "arrow.right")
          .font(.caption2)
        Text("\(I18n.t("after_optimized")) \(SizeFormatter.format(completed.size))")
          .foregroundStyle(ratio < 1 ? Color.green : Color.orange)
        Text("(\(ratio < 1 ? "-" : "+")\(Int(abs(ratio - 1) * 100))%)")
          .foregroundStyle(ratio < 1 ? Color.green : Color.orange)

        Divider()
          .frame(height: 10)

        Text("\(task.inputFormat.displayName) → \(completed.format.displayName)")

        if let resolution = task.inputResolution {
          Divider()
            .frame(height: 10)
          Text("\(resolution.width)×\(resolution.height) → \(completed.width)×\(completed.height)")
        }
      }
    } else if task.isProcessing {
      Text(I18n.t("processing"))
    } else {
      Text(I18n.t("waiting"))
    }
  }

  // MARK: - Canvas

  private var compareCanvas: some View {
    GeometryReader { geo in
      let splitX = geo.size.width * splitFraction

      ZStack {
        Rectangle()
          .fill(.quinary)

        if let inputImage {
          layer(image: inputImage, container: geo.size)
            .mask(alignment: .leading) {
              Rectangle().frame(width: splitX)
            }
        }

        if let outputImage {
          layer(image: outputImage, container: geo.size)
            .mask(alignment: .trailing) {
              Rectangle().frame(width: geo.size.width - splitX)
            }
        }

        if inputImage == nil && outputImage == nil {
          VStack(spacing: 8) {
            if task.isProcessing {
              ProgressView()
              Text(I18n.t("processing"))
                .foregroundStyle(.secondary)
            } else {
              Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        if inputImage != nil && outputImage != nil {
          dividerHandle(at: splitX, containerWidth: geo.size.width, height: geo.size.height)
        }

        if inputImage != nil && outputImage == nil {
          Label(I18n.t("before_optimized"), systemImage: "arrow.left.circle")
            .font(.caption)
            .padding(6)
            .background(.thinMaterial, in: Capsule())
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
      }
      .clipped()
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            panOffset = CGSize(
              width: panAnchor.width + value.translation.width,
              height: panAnchor.height + value.translation.height
            )
          }
          .onEnded { _ in
            panAnchor = panOffset
          }
      )
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            zoom = min(max(zoom * value, 1), 8)
          }
      )
      .onTapGesture(count: 2) {
        withAnimation(.easeOut(duration: 0.2)) {
          zoom = 1
          panOffset = .zero
          panAnchor = .zero
        }
      }
    }
  }

  private func layer(image: NSImage, container: CGSize) -> some View {
    Image(nsImage: image)
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .scaleEffect(zoom, anchor: .center)
      .offset(panOffset)
      .frame(width: container.width, height: container.height)
  }

  private func dividerHandle(at x: CGFloat, containerWidth: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: 0) {
      Rectangle()
        .fill(.white)
        .frame(width: 2)
        .frame(maxHeight: .infinity)
        .shadow(color: .black.opacity(0.4), radius: 1)
      Circle()
        .fill(.white)
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.3), radius: 3)
        .overlay {
          HStack(spacing: 3) {
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right")
          }
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.secondary)
        }
        .contentShape(Circle())
        .gesture(
          DragGesture(minimumDistance: 1)
            .onChanged { value in
              guard containerWidth > 0 else { return }
              splitFraction = min(max(value.location.x / containerWidth, 0.02), 0.98)
            }
        )
    }
    .frame(maxHeight: .infinity)
    .position(x: x, y: height / 2)
  }
}

// MARK: - Task options panel

private struct TaskOptionsPanel: View {
  @Environment(AppStore.self) private var store
  let task: TaskItem

  private enum FormatChoice: Hashable {
    case same
    case format(ImageFormat)
  }

  private var formatChoice: FormatChoice {
    task.outputFormat == task.inputFormat ? .same : .format(task.outputFormat)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(I18n.t("options"))
          .font(.headline)

        VStack(alignment: .leading, spacing: 6) {
          Text(I18n.t("output_format"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Picker(I18n.t("output_format"), selection: Binding(
            get: { formatChoice },
            set: { choice in
              applyChange { options, format in
                switch choice {
                case .same: format = task.inputFormat
                case .format(let newFormat): format = newFormat
                }
                _ = options
              }
            }
          )) {
            Text(I18n.t("original_format")).tag(FormatChoice.same)
            ForEach(ImageFormat.popular) { format in
              Text(format.displayName).tag(FormatChoice.format(format))
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(maxWidth: .infinity)
        }

        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(I18n.t("quality"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text("\(task.options.quality)")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(
            value: Binding(
              get: { Double(task.options.quality) },
              set: { value in
                applyChange { options, _ in
                  options.quality = UInt8(min(max(value, 0), 100))
                }
              }
            ),
            in: 0...100
          )
          .disabled(task.options.lossless == true)
        }

        if task.outputFormat.supportsLossless {
          Toggle(I18n.t("lossless"), isOn: Binding(
            get: { task.options.lossless == true },
            set: { lossless in
              applyChange { options, _ in
                options.lossless = lossless ? true : nil
              }
            }
          ))
        }

        if task.outputFormat == .png {
          Toggle(I18n.t("colors"), isOn: Binding(
            get: { task.options.indexed == true },
            set: { indexed in
              applyChange { options, _ in
                options.indexed = indexed ? true : nil
              }
            }
          ))
        }

        Toggle(I18n.t("preserve_exif"), isOn: Binding(
          get: { task.options.preserveMetadata ?? true },
          set: { preserve in
            applyChange { options, _ in
              options.preserveMetadata = preserve
            }
          }
        ))

        ResizeOptionsEditor(
          resize: Binding(
            get: { task.options.resize },
            set: { newValue in
              applyChange { options, _ in
                options.resize = newValue
              }
            }
          ),
          defaultDimension: defaultResizeDimension
        )
      }
      .padding(16)
    }
  }

  private var defaultResizeDimension: UInt32 {
    UInt32(max(task.inputResolution?.width ?? 1920, 1))
  }

  /// Mutates a draft of the task's current settings and reruns the task.
  private func applyChange(_ mutate: (inout OptimizeOptions, inout ImageFormat) -> Void) {
    var options = task.options
    var format = task.outputFormat
    mutate(&options, &format)
    store.updateTaskOptions(task.id, outputFormat: format, options: options)
  }
}
