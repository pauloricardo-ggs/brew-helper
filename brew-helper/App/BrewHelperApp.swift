import AppKit
import SwiftUI

@main
struct BrewHelperApp: App {
    @State private var store = BrewStore.makeForAppLaunch()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false

    var body: some Scene {
        WindowGroup("Brew Helper", id: "main", for: String.self) { _ in
            ContentView(store: store)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear {
                    enforceReachableAppConfiguration()
                    applyActivationPolicy()
                }
                .onChange(of: hideDockIcon) {
                    enforceReachableAppConfiguration()
                    applyActivationPolicy()
                }
                .onChange(of: showMenuBarExtra) {
                    enforceReachableAppConfiguration()
                    applyActivationPolicy()
                }
        } defaultValue: {
            "main"
        }
        .commands {
            SidebarCommands()
        }

        Settings {
            SettingsView(
                showMenuBarExtra: $showMenuBarExtra,
                hideDockIcon: $hideDockIcon
            )
                .frame(width: 360)
                .padding()
        }

        MenuBarExtra("Brew Helper", systemImage: "mug", isInserted: $showMenuBarExtra) {
            MenuBarServicesView(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    private func enforceReachableAppConfiguration() {
        if hideDockIcon && showMenuBarExtra == false {
            showMenuBarExtra = true
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }
}

private struct SettingsView: View {
    @Binding var showMenuBarExtra: Bool
    @Binding var hideDockIcon: Bool

    var body: some View {
        Form {
            Toggle("Show Brew Helper in the menu bar", isOn: $showMenuBarExtra)

            Toggle("Hide Dock icon", isOn: hideDockBinding)
        }
    }

    private var hideDockBinding: Binding<Bool> {
        Binding {
            hideDockIcon
        } set: { newValue in
            hideDockIcon = newValue
            if newValue {
                showMenuBarExtra = true
            }
        }
    }
}
