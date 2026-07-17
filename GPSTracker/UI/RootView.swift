import SwiftUI

struct RootView: View {
    @Environment(AppLockService.self) private var appLock

    var body: some View {
        ZStack {
            MainTabView()
            if appLock.isLocked {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: appLock.isLocked)
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            LiveMapView()
                .tabItem { Label("Map", systemImage: "map") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct LockScreenView: View {
    @Environment(AppLockService.self) private var appLock

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("GPS Tracker is locked")
                    .font(.headline)
                if let error = appLock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button("Unlock") {
                    Task { await appLock.unlock() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            await appLock.unlock()
        }
    }
}
