import SwiftUI
import AppKit

struct UsageView: View {
    @ObservedObject var usageManager: UsageManager
    @State private var showingSettings: Bool = false
    @State private var loginItemError: String?

    private let thresholdPresets = [25, 50, 75, 90, 95]
    private let refreshOptions = [1, 5, 15, 30]

    // The signature accent — the same teal that anchors the gauge palette.
    private let accent = UsagePalette.safe

    // The popover sizes itself to this content via the hosting controller's
    // preferredContentSize (see AppDelegate), so we just declare a fixed width
    // and let the height be intrinsic — no measure-then-resize, which is what
    // used to leave the popover detached from the menu-bar icon.
    var body: some View {
        content
            .padding()
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { usageManager.updatePercentages() }
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let error = usageManager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(UsagePalette.caution)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(UsagePalette.caution.opacity(0.12))
                .cornerRadius(6)
            }

            if !usageManager.hasFetchedData {
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("WELCOME")
                    Text("Sign in to Claude to start reading your usage.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { openLogin() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle")
                            Text("Sign in to Claude")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accent)
                }
                .padding(.vertical, 8)
            }

            if usageManager.needsReauth {
                Button(action: { openLogin() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Sign in again")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(UsagePalette.danger)
            }

            if usageManager.hasFetchedData {
                gaugeCluster
                footer
            }

            // Account actions — soft capsule buttons, kept quiet beneath the gauges.
            if usageManager.hasCookie {
                HStack(spacing: 8) {
                    accountButton("Sign in again", tint: accent) { openLogin() }
                    accountButton("Sign out", tint: .secondary) { usageManager.clearSessionCookie() }
                    Spacer()
                }
            }

            Button(action: { showingSettings.toggle() }) {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                    Text("SETTINGS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                    Image(systemName: showingSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if showingSettings {
                settings
            }
        }
    }

    // MARK: Header — wordmark + live readout

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CLAUDOMETER")
                .font(.system(size: 13, weight: .heavy))
                .tracking(2.0)
            Spacer()
            if let pct = usageManager.menuBarPercentage() {
                HStack(spacing: 5) {
                    Circle()
                        .fill(UsagePalette.color(for: Double(pct) / 100))
                        .frame(width: 7, height: 7)
                    Text("\(pct)%")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Gauge cluster — the instrument panel

    var gaugeCluster: some View {
        HStack(alignment: .top, spacing: 10) {
            GaugeDial(
                fraction: clampFraction(usageManager.sessionPercentage),
                label: "Session",
                detail: resetDetail(usageManager.sessionResetsAt)
            )
            GaugeDial(
                fraction: clampFraction(usageManager.weeklyPercentage),
                label: "Weekly",
                detail: resetDetail(usageManager.weeklyResetsAt)
            )
            if usageManager.hasWeeklySonnet {
                GaugeDial(
                    fraction: clampFraction(usageManager.weeklySonnetPercentage),
                    label: "Sonnet",
                    detail: resetDetail(usageManager.weeklySonnetResetsAt)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Footer — last updated + refresh

    var footer: some View {
        HStack(spacing: 8) {
            Text("Updated \(formatTime(usageManager.lastUpdated))")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button(action: { usageManager.fetchUsage() }) {
                Image(systemName: usageManager.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .help("Refresh now")
        }
    }

    // MARK: Settings

    var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("GENERAL")
            Toggle(isOn: Binding(
                get: { usageManager.openAtLogin },
                set: { loginItemError = usageManager.setOpenAtLogin($0) }
            )) {
                settingLabel("Open at login", "Launch automatically when you log in")
            }
            .toggleStyle(.checkbox)
            .tint(accent)

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption2)
                    .foregroundColor(UsagePalette.danger)
            }

            hairline

            // Menu-bar display metric.
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("MENU BAR READS")
                Picker("", selection: Binding(
                    get: { usageManager.menuBarMetric },
                    set: { usageManager.setMenuBarMetric($0) }
                )) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Refresh interval.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("REFRESH EVERY")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { usageManager.refreshIntervalMinutes },
                        set: { usageManager.setRefreshInterval($0) }
                    )) {
                        ForEach(refreshOptions, id: \.self) { min in
                            Text("\(min) min").tag(min)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                Text("Polls more often automatically as you near a limit.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            hairline

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { usageManager.usageNotificationsEnabled },
                    set: { usageManager.setNotificationsEnabled($0) }
                )) {
                    settingLabel("Usage alerts", "Notify at the thresholds below")
                }
                .toggleStyle(.checkbox)
                .tint(accent)

                if usageManager.usageNotificationsEnabled {
                    HStack(spacing: 6) {
                        ForEach(thresholdPresets, id: \.self) { threshold in
                            thresholdChip(threshold)
                        }
                    }
                }

                Button("Send a test alert") { usageManager.sendTestNotification() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(accent)
            }

            hairline

            Toggle(isOn: Binding(
                get: { usageManager.shortcutEnabled },
                set: { usageManager.setShortcutEnabled($0) }
            )) {
                settingLabel("Global shortcut (⌘U)", "Toggle the panel from anywhere.\nDisable if it conflicts with other apps.")
            }
            .toggleStyle(.switch)
            .tint(accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 0.5)
                )
        )
    }

    // A selectable notification-threshold chip; tinted with the signature accent
    // when active.
    @ViewBuilder
    func thresholdChip(_ threshold: Int) -> some View {
        let active = usageManager.notificationThresholds.contains(threshold)
        if active {
            Button("\(threshold)%") { usageManager.toggleThreshold(threshold) }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(accent)
        } else {
            Button("\(threshold)%") { usageManager.toggleThreshold(threshold) }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(accent)
        }
    }

    /// A soft capsule button for the secondary account actions.
    func accountButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    /// A small, all-caps tracked section heading — the same instrument-label
    /// treatment used under the gauges.
    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .tracking(1.0)
            .foregroundColor(.secondary)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(height: 0.5)
    }

    func settingLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).fontWeight(.medium)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    func openLogin() {
        (NSApplication.shared.delegate as? AppDelegate)?.showLogin()
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Clamp a published percentage (0–1, but defensively bounded) for a gauge.
    func clampFraction(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// Compact "until reset" string shown under a gauge: "2h 14m", "3d 4h",
    /// "<1m". nil when the reset time is unknown or already past.
    func resetDetail(_ date: Date?) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "<1m" }
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}