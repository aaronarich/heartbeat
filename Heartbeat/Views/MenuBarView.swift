//
//  MenuBarView.swift
//  Heartbeat
//

import SwiftUI
import AppKit

/// Status item content: CPU load plus the CPU (or SoC die) temperature.
struct MenuBarLabel: View {
    let monitor: SystemMonitor

    var body: some View {
        Label {
            Text(text)
                .monospacedDigit()
        } icon: {
            Image(systemName: "waveform.path.ecg")
        }
    }

    private var text: String {
        guard let snapshot = monitor.snapshot else { return "—" }
        var parts = [Formatters.percent(snapshot.cpu.busy)]
        if let temperature = snapshot.temperatures.cpuAverage ?? snapshot.temperatures.dieAverage {
            parts.append(Formatters.temperatureCompact(temperature))
        }
        return parts.joined(separator: " · ")
    }
}

/// Compact popover shown when the status item is clicked.
struct MenuBarView: View {
    @Environment(SystemMonitor.self) private var monitor
    @Environment(LoginItemManager.self) private var loginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = monitor.snapshot {
                HStack {
                    Text(monitor.systemInfo.chipName)
                        .font(.headline)
                    Spacer()
                    StatusBadge(text: snapshot.thermalState.label, systemImage: "flame",
                                color: snapshot.thermalState.color)
                }

                MeterRow(title: "CPU",
                         value: Formatters.percent(snapshot.cpu.busy),
                         fraction: snapshot.cpu.busy,
                         color: SeriesColor.primary)

                MeterRow(title: "Memory",
                         value: "\(Formatters.bytes(snapshot.memory.used)) of \(Formatters.bytes(snapshot.memory.total))",
                         fraction: snapshot.memory.usedFraction,
                         color: SeriesColor.primary)

                if let temperature = snapshot.temperatures.cpuAverage ?? snapshot.temperatures.dieAverage {
                    let level = TemperatureLevel(celsius: temperature)
                    MeterRow(title: snapshot.temperatures.cpuAverage == nil ? "SoC die" : "CPU temperature",
                             value: "\(Formatters.temperature(temperature)) · \(level.label)",
                             fraction: min(temperature / 110, 1),
                             color: level.color)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Label("Network", systemImage: "network")
                            .foregroundStyle(.secondary)
                        rate("arrow.down", snapshot.network.downloadBytesPerSecond)
                        rate("arrow.up", snapshot.network.uploadBytesPerSecond)
                    }
                    GridRow {
                        Label("Disk", systemImage: "internaldrive")
                            .foregroundStyle(.secondary)
                        rate("arrow.down", snapshot.disk.readBytesPerSecond)
                        rate("arrow.up", snapshot.disk.writeBytesPerSecond)
                    }
                }
                .font(.callout)
            } else {
                ProgressView("Reading vitals…")
                    .frame(maxWidth: .infinity)
            }

            Divider()

            loginItemRow

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: DashboardWindow.id)
                    NSApplication.shared.activate()
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { loginItem.refresh() }
    }

    private var loginItemRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled || loginItem.needsApproval },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.callout)

            if loginItem.needsApproval {
                HStack(spacing: 4) {
                    Text("Needs approval in System Settings.")
                    Button("Open") { loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let error = loginItem.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func rate(_ symbol: String, _ bytesPerSecond: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(Formatters.rate(bytesPerSecond))
                .monospacedDigit()
        }
        .frame(minWidth: 80, alignment: .leading)
    }
}

/// Title and value over a thin tinted bar.
struct MeterRow: View {
    let title: String
    let value: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .font(.callout)
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(color)
        }
    }
}

#if DEBUG
#Preview("Menu bar popover") {
    MenuBarView()
        .environment(SystemMonitor(previewSnapshot: PreviewData.snapshot, info: PreviewData.info))
        .environment(LoginItemManager())
}
#endif

