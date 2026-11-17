//
//  LoginItemManager.swift
//  Heartbeat
//

import Foundation
import Observation
import ServiceManagement
import os

/// Registers the app as a login item through `SMAppService`.
@Observable
final class LoginItemManager {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    /// Bool preference. Absent means the app has never launched before.
    private static let preferenceKey = "launchAtLogin"
    private let logger = Logger(subsystem: "com.aaronrich.Heartbeat", category: "LoginItem")

    var isEnabled: Bool { status == .enabled }
    /// True when the user has to approve the item in System Settings before it takes effect.
    var needsApproval: Bool { status == .requiresApproval }

    /// Re-reads the status; the user can change it in System Settings at any time.
    func refresh() {
        status = SMAppService.mainApp.status
        logger.info("Login item status: \(String(describing: self.status), privacy: .public)")
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            logger.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.set(enabled, forKey: Self.preferenceKey)
        refresh()
    }

    /// Call once at launch. Opts in on the very first run. On later runs it re-registers
    /// only when the system reports the item as not found, which happens after the app
    /// bundle is rebuilt or moved. If the user removed it in System Settings the status
    /// is "not registered" instead, and that choice is left alone.
    func applyPreferenceAtLaunch() {
        guard let wantsLaunchAtLogin = UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool else {
            setEnabled(true)
            return
        }
        if wantsLaunchAtLogin, status == .notFound {
            setEnabled(true)
        } else {
            refresh()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
