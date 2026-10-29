import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    CacheStore.setup()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    CacheStore.clearAll()
    return .terminateNow
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    AppStore.shared.addURLs(urls)
  }
}

@main
struct IMGoApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var store = AppStore.shared

  var body: some Scene {
    Window("IMGX", id: "main") {
      ContentView()
        .environment(store)
    }
    .defaultSize(width: 1140, height: 800)
    .commands {
      CommandGroup(replacing: .newItem) {
        Button(I18n.t("open")) {
          if let urls = ImportService.pickFiles() {
            AppStore.shared.addURLs(urls)
          }
        }
        .keyboardShortcut("o")

        Button(I18n.t("open_dir")) {
          if let folder = ImportService.pickFolder() {
            AppStore.shared.addFolder(folder)
          }
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
      }

      CommandGroup(replacing: .saveItem) {
        Button(I18n.t("save")) {
          AppStore.shared.saveCompleted(trigger: .override)
        }
        .keyboardShortcut("s")

        Button(I18n.t("save_new_file")) {
          AppStore.shared.saveCompleted(trigger: .autoNewName)
        }

        Button(I18n.t("save_to_dir")) {
          AppStore.shared.saveCompleted(trigger: .saveToDir)
        }
      }
    }
  }
}

extension AppTheme {
  var colorScheme: ColorScheme? {
    switch self {
    case .light: .light
    case .dark: .dark
    case .system: nil
    }
  }
}
