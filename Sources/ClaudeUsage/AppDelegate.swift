import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let usageClient = UsageClient()
    private var refreshTimer: Timer?

    private var lastSnapshot: UsageSnapshot?
    private var lastError: UsageError?
    private var isStale = false

    private let fiveHourInfoItem = NSMenuItem(title: "5-hour: —", action: nil, keyEquivalent: "")
    private let weeklyInfoItem = NSMenuItem(title: "Weekly: —", action: nil, keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    // Rebuilt on every refresh since the set of models with their own scoped
    // limit can change (e.g. Sonnet/Fable/Opus each only show up here while
    // they actually have a distinct weekly cap active).
    private var modelLimitItems: [NSMenuItem] = []
    private weak var menu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let menu = NSMenu()
        menu.delegate = self

        fiveHourInfoItem.isEnabled = false
        weeklyInfoItem.isEnabled = false
        menu.addItem(fiveHourInfoItem)
        menu.addItem(weeklyInfoItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.menu = menu
        updateIcon()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.performRefresh()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        performRefresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        performRefresh()
    }

    @objc private func handleWake() {
        performRefresh()
    }

    @objc private func refreshNow() {
        performRefresh()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            NSLog("Failed to toggle launch at login: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func performRefresh() {
        usageClient.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.lastSnapshot = snapshot
                    self.lastError = nil
                    self.isStale = false
                case .failure(let error):
                    self.lastError = error
                    if self.lastSnapshot != nil {
                        // Keep showing the last known values but mark them stale.
                        self.isStale = true
                    }
                }
                self.updateIcon()
                self.updateMenuText()
            }
        }
    }

    private func updateIcon() {
        let fiveHour = lastSnapshot?.fiveHour.utilization
        let weekly = lastSnapshot?.sevenDay.utilization
        let showStale = isStale || (lastSnapshot == nil && lastError != nil)
        statusItem.button?.image = RingIcon.make(fiveHourPercent: fiveHour, weeklyPercent: weekly, isStale: showStale)

        if let snapshot = lastSnapshot {
            let suffix = isStale ? " (stale)" : ""
            statusItem.button?.toolTip = "5-hour: \(Int(snapshot.fiveHour.utilization))%  •  Weekly: \(Int(snapshot.sevenDay.utilization))%\(suffix)"
        } else {
            statusItem.button?.toolTip = "Claude Usage — unavailable"
        }
    }

    private func updateMenuText() {
        if let snapshot = lastSnapshot {
            let staleSuffix = isStale ? "  (stale)" : ""
            fiveHourInfoItem.title = "5-hour: \(Int(snapshot.fiveHour.utilization))%\(resetSuffix(for: snapshot.fiveHour.resetsAt))\(staleSuffix)"
            weeklyInfoItem.title = "Weekly: \(Int(snapshot.sevenDay.utilization))%\(resetSuffix(for: snapshot.sevenDay.resetsAt))\(staleSuffix)"
            updateModelLimitItems(snapshot.modelWeeklyLimits, staleSuffix: staleSuffix)
        } else if let error = lastError {
            fiveHourInfoItem.title = message(for: error)
            weeklyInfoItem.title = "No data yet"
            updateModelLimitItems([], staleSuffix: "")
        }
    }

    private func updateModelLimitItems(_ limits: [ModelWeeklyLimit], staleSuffix: String) {
        guard let menu else { return }

        for item in modelLimitItems {
            menu.removeItem(item)
        }
        modelLimitItems.removeAll()

        let weeklyIndex = menu.index(of: weeklyInfoItem)
        guard weeklyIndex >= 0 else { return }

        for (offset, limit) in limits.enumerated() {
            let item = NSMenuItem(
                title: "  \(limit.modelName) weekly: \(Int(limit.utilization))%\(resetSuffix(for: limit.resetsAt))\(staleSuffix)",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.insertItem(item, at: weeklyIndex + 1 + offset)
            modelLimitItems.append(item)
        }
    }

    private func resetSuffix(for date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return " — resets \(formatter.string(from: date))"
    }

    private func message(for error: UsageError) -> String {
        switch error {
        case .noCredentials, .badCredentials, .unauthorized:
            return "Open Claude Code to refresh credentials"
        case .network:
            return "Network error"
        case .decode:
            return "Unexpected response"
        }
    }
}
