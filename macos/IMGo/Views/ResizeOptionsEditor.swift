import SwiftUI

/// Shared resize editor used by the per-image options panel, the global
/// conversion profiles, and the batch resize popover. A nil binding means
/// resize is disabled. Width/height commit on submit so intermediate typing
/// never triggers a re-encode.
struct ResizeOptionsEditor: View {
  @Binding var resize: ResizeOptions?
  var defaultDimension: UInt32 = 1920

  @State private var widthText = ""
  @State private var heightText = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(I18n.t("resize"), isOn: Binding(
        get: { resize != nil },
        set: { enabled in
          if enabled {
            resize = ResizeOptions(
              width: UInt32(widthText) ?? defaultDimension,
              height: UInt32(heightText) ?? defaultDimension,
              type: .downsizeContain
            )
          } else {
            resize = nil
          }
        }
      ))

      if resize != nil {
        HStack {
          dimensionField(label: I18n.t("width"), text: $widthText)
          dimensionField(label: I18n.t("height"), text: $heightText)
        }

        Picker(I18n.t("resize"), selection: Binding(
          get: { resize?.type ?? .downsizeContain },
          set: { type in
            resize?.type = type
          }
        )) {
          Text(I18n.t("resize_contain")).tag(ResizeType.downsizeContain)
          Text(I18n.t("resize_cover")).tag(ResizeType.downsizeCover)
          Text(I18n.t("resize_stretch")).tag(ResizeType.exact)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
    }
    .onAppear {
      syncTextFields()
    }
    .onChange(of: resize) { oldValue, newValue in
      // Only dimension changes (or clearing) override in-progress typing;
      // type-only switches leave the uncommitted text fields alone.
      if oldValue?.width != newValue?.width
        || oldValue?.height != newValue?.height
        || newValue == nil {
        syncTextFields()
      }
    }
  }

  private func dimensionField(label: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      TextField(label, text: text)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
          commitDimensions()
        }
    }
  }

  private func commitDimensions() {
    guard resize != nil else { return }
    resize = ResizeOptions(
      width: UInt32(widthText) ?? resize?.width ?? defaultDimension,
      height: UInt32(heightText) ?? resize?.height ?? defaultDimension,
      type: resize?.type ?? .downsizeContain
    )
  }

  private func syncTextFields() {
    if let resize {
      widthText = String(resize.width)
      heightText = String(resize.height)
    } else {
      widthText = ""
      heightText = ""
    }
  }
}
