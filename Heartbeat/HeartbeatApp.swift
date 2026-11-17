//
//  HeartbeatApp.swift
//  Heartbeat
//
//  Created by Aaron A. Rich on 11/17/26.
//

import SwiftUI

@main
struct HeartbeatApp: App {
    /// One monitor shared by the status item, the popover and the dashboard window.
    @State private var monitor = SystemMonitor()
    @State private var loginItem: LoginItemManager

    init() {
        let loginItem = LoginItemManager()
        loginItem.applyPreferenceAtLaunch()
        _loginItem = State(initialValue: loginItem)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(monitor)
                .environment(loginItem)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        // Full dashboard, opened from the popover. Suppressed at launch so the app
        // starts as a menu bar item only.
        Window("Heartbeat", id: DashboardWindow.id) {
            ContentView()
                .environment(monitor)
        }
        .defaultSize(width: 1160, height: 820)
        .defaultLaunchBehavior(.suppressed)
    }
}

enum DashboardWindow {
    static let id = "dashboard"
}
