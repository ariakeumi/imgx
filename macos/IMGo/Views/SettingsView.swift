import SwiftUI

struct SettingsView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  @State private var draft: AppOptions = AppOptions()
  @State private var ratioText = ""

  var body: some View {
    VStack(spacing: 0) {
      header

      Divider()

      Form {
        Section(I18n.t("general")) {
          Picker(I18n.t("theme_color"), selection: $draft.appTheme) {
            Text(I18n.t("light")).tag(AppTheme.light)
            Text(I18n.t("dark")).tag(AppTheme.dark)
            Text(I18n.t("follow_system")).tag(AppTheme.system)
          }

        }

        Section(I18n.t("skip_oversized")) {
          Picker(I18n.t("skip_method"), selection: $draft.skipSaveType) {
            Text(I18n.t("skip_none")).tag(SkipSaveType.none)
            Text(I18n.t("same_format")).tag(SkipSaveType.sameFormat)
            Text(I18n.t("all_formats")).tag(SkipSaveType.all)
          }

          HStack {
            Text(I18n.t("skip_ratio"))
            TextField("1.0", text: $ratioText)
              .textFieldStyle(.roundedBorder)
              .frame(width: 90)
          }
          Text(I18n.t("skip_save_warning"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section {
          HStack {
            Text(I18n.t("new_file_name_suffix"))
            TextField("-min", text: $draft.newFileNameSuffix)
              .textFieldStyle(.roundedBorder)
          }
          Text(I18n.t("new_file_name_suffix_description"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Section(I18n.t("conversion_profiles")) {
          ForEach($draft.globalDefaultOptions) { $profile in
            ProfileEditor(profile: $profile, onDelete: {
              draft.globalDefaultOptions.removeAll { $0.id == profile.id }
            })
          }
          .onMove { from, to in
            draft.globalDefaultOptions.move(fromOffsets: from, toOffset: to)
          }

          Button(I18n.t("add_conversion_profile")) {
            draft.globalDefaultOptions.append(GlobalDefaultOptions(
              inputFormats: [],
              outputFormat: nil,
              options: OptimizeOptions(indexed: false, quality: 75)
            ))
          }
        }
      }
      .formStyle(.grouped)

      Divider()

      footer
    }
    .frame(minWidth: 560, idealWidth: 620, minHeight: 520, idealHeight: 620)
    .onAppear {
      draft = store.appOptions
      ratioText = String(format: "%.2f", store.appOptions.skipSaveMinRatio)
    }
  }

  private var header: some View {
    HStack {
      Text(I18n.t("open_settings"))
        .font(.headline)
      Spacer()
    }
    .padding(16)
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button(I18n.t("cancel")) {
        dismiss()
      }
      Button(I18n.t("apply_now")) {
        var options = draft
        options.skipSaveMinRatio = Double(ratioText.replacingOccurrences(of: ",", with: ".")) ?? 1.0
        store.updateAppOptions(options, rerunAll: true)
        dismiss()
      }
      .keyboardShortcut(.defaultAction)
    }
    .padding(12)
  }
}

// MARK: - Profile editor

private struct ProfileEditor: View {
  @Binding var profile: GlobalDefaultOptions
  let onDelete: () -> Void

  private enum OutputChoice: Hashable {
    case same
    case format(ImageFormat)
  }

  private var outputChoice: OutputChoice {
    profile.outputFormat.map(OutputChoice.format) ?? .same
  }

  private var summary: String {
    if profile.inputFormats.isEmpty {
      return I18n.t("all_formats")
    }
    return profile.inputFormats.map(\.displayName).sorted().joined(separator: ", ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Menu {
          Button(I18n.t("all_formats")) {
            profile.inputFormats = []
          }
          Divider()
          ForEach(Array(ImageFormat.popular)) { format in
            Button {
              if let index = profile.inputFormats.firstIndex(of: format) {
                profile.inputFormats.remove(at: index)
              } else {
                profile.inputFormats.append(format)
              }
            } label: {
              if profile.inputFormats.contains(format) {
                Label(format.displayName, systemImage: "checkmark")
              } else {
                Text(format.displayName)
              }
            }
          }
        } label: {
          Text("\(I18n.t("input_formats")): \(summary)")
        }

        Spacer()

        Button {
          onDelete()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help(I18n.t("delete_conversion_profile"))
      }

      Picker(I18n.t("output_format"), selection: Binding(
        get: { outputChoice },
        set: { choice in
          if case .format(let format) = choice {
            profile.outputFormat = format
          } else {
            profile.outputFormat = nil
          }
        }
      )) {
        Text(I18n.t("original_format")).tag(OutputChoice.same)
        ForEach(ImageFormat.popular) { format in
          Text(format.displayName).tag(OutputChoice.format(format))
        }
      }

      HStack {
        Text("\(I18n.t("quality")) \(profile.options.quality)")
          .font(.caption)
          .foregroundStyle(.secondary)
        Slider(
          value: Binding(
            get: { Double(profile.options.quality) },
            set: { profile.options.quality = UInt8(min(max($0, 0), 100)) }
          ),
          in: 0...100
        )
      }

      ResizeOptionsEditor(resize: $profile.options.resize)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
  }
}
