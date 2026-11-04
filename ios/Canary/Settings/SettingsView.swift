import StoreKit
import SwiftUI

/// Canary+, alerts, pinned signals and information about the method.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlusStore.self) private var plus
    @Environment(PinStore.self) private var pins
    @Environment(BoardStore.self) private var store

    @State private var showsPaywall = false
    @State private var showsPinEditor = false
    @State private var showsManage = false
    @State private var alertsOn = SharedSettings.alertsEnabled
    @State private var scope = SharedSettings.alertScope
    @State private var permissionDenied = false

    var body: some View {
        NavigationStack {
            Form {
                plusSection
                alertsSection
                Section {
                    Button {
                        showsPinEditor = true
                    } label: {
                        LabeledContent("Pinned Signals") {
                            // "2 of 3" on the free plan; just the count with Canary+ or over the limit
                            // (pins are kept if a subscription lapses).
                            let count = pins.ids.count
                            Text(plus.isPlus || count > PlusFeature.freePinLimit
                                 ? "\(count)" : "\(count) of \(PlusFeature.freePinLimit)")
                        }
                    }
                    .foregroundStyle(.primary)
                }
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // iOS 26 sheets close with the system's glass ✕ button.
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .sheet(isPresented: $showsPaywall) { CanaryPlusView(reason: .general) }
            .sheet(isPresented: $showsPinEditor) { PinEditorView() }
            .manageSubscriptionsSheet(isPresented: $showsManage)
            .opensLinksInApp()
            .onChange(of: plus.isPlus) { _, isPlus in
                if !isPlus { alertsOn = false }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var plusSection: some View {
        Section {
            if plus.isPlus {
                Label("Canary+ is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.primary)
                Button("Manage Subscription") { showsManage = true }
            } else {
                Button {
                    showsPaywall = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "bird.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.yellow.mix(with: .orange, by: 0.3).gradient, in: .rect(cornerRadius: 10, style: .continuous))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Get Canary+")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Alerts, unlimited pins and signal widgets")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Button("Restore Purchases") { Task { await plus.restore() } }
        }
    }

    @ViewBuilder private var alertsSection: some View {
        Section {
            Toggle("Status-Change Alerts", isOn: Binding(
                get: { alertsOn && plus.isPlus },
                set: { newValue in Task { await setAlerts(newValue) } }
            ))
            if alertsOn, plus.isPlus {
                Picker("Alert Me About", selection: $scope) {
                    ForEach(AlertScope.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: scope) { _, value in SharedSettings.alertScope = value }
            }
        } header: {
            Text("Alerts")
        } footer: {
            if permissionDenied {
                Text("Notifications are off for Canary. Turn them on in the Settings app under Notifications.")
            } else {
                Text("Canary checks for changes in the background. iOS decides when that happens, so an alert can arrive a few hours after the board changes. Nothing about you leaves this iPhone.")
            }
        }
    }

    @ViewBuilder private var aboutSection: some View {
        Section("About") {
            Link(destination: AppConstants.methodologyURL) {
                Label("How Canary Works", systemImage: "book")
            }
            Link(destination: AppConstants.websiteURL) {
                Label("Canary on the Web", systemImage: "safari")
            }
            Link(destination: AppConstants.privacyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }
            LabeledContent("Data Licence", value: store.board?.status.licence?.name ?? "CC BY 4.0")
            LabeledContent("Version", value: Bundle.main.versionString)
        }
        Section {
        } footer: {
            Text("Attention levels describe current conditions. They are not a forecast, and not financial, medical, legal or safety advice. For your safety, follow official guidance.")
        }
    }

    // MARK: Actions

    private func setAlerts(_ on: Bool) async {
        guard on else {
            alertsOn = false
            SharedSettings.alertsEnabled = false
            AlertService.shared.scheduleRefresh(after: nil)
            return
        }
        guard plus.isPlus else {
            showsPaywall = true
            return
        }
        let granted = await AlertService.shared.requestPermission()
        permissionDenied = !granted
        alertsOn = granted
        SharedSettings.alertsEnabled = granted
        if granted, let board = store.board { AlertService.shared.markSeen(board) }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
