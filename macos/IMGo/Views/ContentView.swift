import SwiftUI

struct ContentView: View {
  @Environment(AppStore.self) private var store

  private var activeTaskBinding: Binding<TaskItem?> {
    Binding(
      get: { store.tasks.first { $0.id == store.activeTaskId } },
      set: { store.setActiveTask($0?.id) }
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      HeaderView()
      Divider()
      if store.tasks.isEmpty && store.addLoading.activeIds.isEmpty {
        EmptyStateView()
      } else {
        TaskListView()
      }
    }
    .frame(minWidth: 640, minHeight: 360)
    .background()
    .preferredColorScheme(store.appOptions.appTheme.colorScheme)
    .dropDestination(for: URL.self) { urls, _ in
      let importable = urls.filter { ImageFormat.detect(fromPath: $0.path) != nil }
      guard !importable.isEmpty else { return false }
      store.addURLs(importable)
      return true
    }
    .overlay(alignment: .bottom) {
      if let toast = store.toast {
        ToastView(toast: toast)
          .padding(.bottom, 20)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.2), value: store.toast?.id)
    .sheet(isPresented: Binding(
      get: { store.settingsVisible },
      set: { store.settingsVisible = $0 }
    )) {
      SettingsView()
    }
    .sheet(item: activeTaskBinding) { task in
      CompareView(task: task)
    }
  }
}

// MARK: - Header

private struct HeaderView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    HStack(spacing: 12) {
      Button(I18n.t("choose_images")) {
        if let urls = ImportService.pickFiles() {
          store.addURLs(urls)
        }
      }

      Button(I18n.t("select_folder")) {
        if let folder = ImportService.pickFolder() {
          store.addFolder(folder)
        }
      }

      if !store.tasks.isEmpty {
        BatchResizeButton()
      }

      Spacer()

      progressSummary

      Spacer()

      if !store.tasks.isEmpty {
        Menu {
          Button(I18n.t("save_new_file")) {
            store.saveCompleted(trigger: .autoNewName)
          }
          Button(I18n.t("save_to_dir")) {
            store.saveCompleted(trigger: .saveToDir)
          }
          Divider()
          Button(I18n.t("save_override")) {
            store.saveCompleted(trigger: .override)
          }
        } label: {
          Label(I18n.t("save_completed"), systemImage: "square.and.arrow.down")
        }
        .disabled(!store.tasks.contains { $0.completedResult != nil })

        Button(I18n.t("clear"), role: .destructive) {
          store.removeAllTasks()
        }
      }

      Button {
        store.settingsVisible = true
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(.borderless)
      .help(I18n.t("open_settings"))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var progressSummary: some View {
    let processing = store.processingCount
    let total = store.tasks.count
    let adding = !store.addLoading.activeIds.isEmpty

    if adding {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text(store.addLoading.latestFileName.isEmpty
          ? I18n.t("loading")
          : store.addLoading.latestFileName)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
          .frame(maxWidth: 240)
      }
    } else if processing > 0 {
      HStack(spacing: 8) {
        ProgressView(value: Double(total - processing), total: Double(max(total, 1)))
          .frame(width: 120)
        Text("\(total - processing)/\(total)")
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
    }
  }
}

// MARK: - Batch resize

private struct BatchResizeButton: View {
  @State private var isVisible = false

  var body: some View {
    Button {
      isVisible.toggle()
    } label: {
      Label(I18n.t("resize"), systemImage: "arrow.down.right.and.arrow.up.left")
    }
    .help(I18n.t("batch_resize"))
    .popover(isPresented: $isVisible, arrowEdge: .bottom) {
      BatchResizePopover()
    }
  }
}

private struct BatchResizePopover: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var percentageText = "50"
  @FocusState private var focused: Bool

  private var percentage: Double? {
    guard let value = Int(percentageText.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "%", with: "")),
      (1...400).contains(value) else { return nil }
    return Double(value)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(I18n.t("batch_resize")).font(.headline)
      HStack {
        Text(I18n.t("resize_percentage"))
        TextField("50", text: $percentageText)
          .textFieldStyle(.roundedBorder)
          .focused($focused)
          .onSubmit { apply() }
        Text("%")
      }
      Text(I18n.t("resize_percentage_hint"))
        .font(.caption)
        .foregroundStyle(.secondary)
      if percentage == nil {
        Text(I18n.t("resize_percentage_invalid"))
          .font(.caption).foregroundStyle(.orange)
      }
      if !store.canScaleAllTasks {
        Text(I18n.t("resize_wait_for_dimensions"))
          .font(.caption).foregroundStyle(.secondary)
      }
      Text(I18n.tpl("batch_resize_description", String(store.tasks.count)))
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button(I18n.t("apply_now")) { apply() }
          .keyboardShortcut(.defaultAction)
          .disabled(percentage == nil || !store.canScaleAllTasks)
      }
    }
    .padding(16)
    .frame(width: 300)
    .onAppear {
      focused = true
    }
  }

  private func apply() {
    guard let percentage, store.applyScaleToAllTasks(percentage) else { return }
    dismiss()
  }
}

// MARK: - Empty state

private struct EmptyStateView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 56))
        .foregroundStyle(.tertiary)
      Text(I18n.t("drag_images_here"))
        .font(.title3)
        .foregroundStyle(.secondary)
      HStack {
        Button(I18n.t("choose_images")) {
          if let urls = ImportService.pickFiles() {
            store.addURLs(urls)
          }
        }
        Button(I18n.t("select_folder")) {
          if let folder = ImportService.pickFolder() {
            store.addFolder(folder)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(
          style: StrokeStyle(lineWidth: 2, dash: [8, 6])
        )
        .foregroundStyle(.quaternary)
        .padding(24)
    )
  }
}

// MARK: - Toast

private struct ToastView: View {
  let toast: AppStore.Toast

  var body: some View {
    VStack(spacing: 2) {
      if !toast.title.isEmpty {
        Text(toast.title)
          .font(.callout.weight(.medium))
      }
      Text(toast.description)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(
      Capsule().fill(.background).shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    )
    .overlay(
      Capsule().strokeBorder(.quaternary)
    )
  }
}
