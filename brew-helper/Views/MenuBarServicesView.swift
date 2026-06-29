import AppKit
import SwiftUI

struct MenuBarServicesView: View {
    @Bindable var store: BrewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Homebrew Services")
                    .font(.headline)
                
                Spacer()

                RefreshMenuBarControl(isLoading: store.isLoading) {
                    Task { await store.loadServices() }
                }
            }
            .padding(.horizontal, 16)
            
            if store.services.isEmpty {
                ContentUnavailableView("No Services", systemImage: "server.rack")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.services) { service in
                            MenuBarServiceRow(service: service, isLoading: store.isServiceLoading(service)) {
                                Task { await store.start(service) }
                            } stopAction: {
                                Task { await store.stop(service) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 600)
            }
        }
        .padding(.top, 16)
        .frame(width: 400)
        .frame(minHeight: 220, maxHeight: 600)
        .task {
            await store.loadServices()
        }
    }
}

private struct MenuBarServiceRow: View {
    let service: BrewService
    let isLoading: Bool
    let startAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: service.status.systemImage)
                .foregroundStyle(statusStyle)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .lineLimit(1)
                Text(service.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        service.status == .started ? stopAction() : startAction()
                    } label: {
                        Label(service.status == .started ? "Stop" : "Start", systemImage: service.status == .started ? "stop.fill" : "play.fill")
                    }
                    .labelStyle(.iconOnly)
                    .help(service.status == .started ? "Stop service" : "Start service")
                }
            }
            .frame(width: 32, height: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    private var statusStyle: Color {
        switch service.status {
        case .started:
            Color(red: 0.38, green: 0.62, blue: 0.46)
        case .stopped:
            Color(red: 1.0, green: 0.5, blue: 0.5)
        case .unknown:
            Color(red: 0.72, green: 0.55, blue: 0.30)
        }
    }
}

private struct RefreshMenuBarControl: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: action) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .padding(4)
                }
                .buttonBorderShape(.circle)
                .help("Refresh services")
            }
        }
        .frame(width: 32, height: 32)
    }
}
