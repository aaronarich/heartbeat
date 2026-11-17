//
//  VitalCards.swift
//  Heartbeat
//

import SwiftUI

// MARK: - CPU

struct CPUCard: View {
    let sample: CPUSample
    let history: [SeriesPoint]
    let window: ClosedRange<Date>
    let info: SystemInfo

    var body: some View {
        VitalCard(title: "CPU", systemImage: "cpu") {
            HStack(alignment: .center, spacing: 20) {
                Gauge(value: sample.busy, in: 0...1) {
                    Text("CPU")
                } currentValueLabel: {
                    Text(Formatters.percent(sample.busy))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(SeriesColor.primary)
                .scaleEffect(1.3)
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    LegendRow(color: SeriesColor.primary, label: "User", value: Formatters.percent(sample.user))
                    LegendRow(color: SeriesColor.secondary, label: "System", value: Formatters.percent(sample.system))
                    LegendRow(color: SeriesColor.neutral, label: "Idle", value: Formatters.percent(sample.idle))
                }
            }

            TwoSeriesChart(points: history, primaryLabel: "User", secondaryLabel: "System",
                           style: .stackedArea, window: window, yDomain: 0...100) { value in
                "\(Int(value))%"
            }

            CoreLoadGrid(perCore: sample.perCore, efficiencyCores: info.efficiencyCores)
        }
    }
}

/// One thin vertical bar per logical core. On Apple silicon the kernel lists
/// efficiency cores first, so the first `efficiencyCores` bars are labeled E.
struct CoreLoadGrid: View {
    let perCore: [Double]
    let efficiencyCores: Int

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: min(max(perCore.count, 1), 8))
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(perCore.enumerated()), id: \.offset) { index, load in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SeriesColor.primary)
                            .frame(height: max(3, 36 * load))
                    }
                    .frame(height: 36)
                    Text(label(for: index))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .help("\(label(for: index)): \(Formatters.percent(load))")
                .accessibilityLabel("\(label(for: index)) \(Formatters.percent(load))")
            }
        }
    }

    private func label(for index: Int) -> String {
        guard efficiencyCores > 0 else { return "\(index + 1)" }
        return index < efficiencyCores ? "E\(index + 1)" : "P\(index - efficiencyCores + 1)"
    }
}

// MARK: - Memory

struct MemoryCard: View {
    let sample: MemorySample

    var body: some View {
        VitalCard(title: "Memory", systemImage: "memorychip") {
            HStack(alignment: .center, spacing: 20) {
                Gauge(value: sample.usedFraction, in: 0...1) {
                    Text("Memory")
                } currentValueLabel: {
                    Text(Formatters.percent(sample.usedFraction))
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(SeriesColor.primary)
                .scaleEffect(1.3)
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    StatValue(value: "\(Formatters.bytes(sample.used)) of \(Formatters.bytes(sample.total))", caption: "Memory used")
                    StatusBadge(text: "Pressure: \(sample.pressure.rawValue)",
                                systemImage: sample.pressure.symbolName,
                                color: sample.pressure.color)
                }
            }

            SegmentedBar(segments: [
                .init(label: "App", value: Double(sample.appMemory), color: SeriesColor.primary),
                .init(label: "Wired", value: Double(sample.wired), color: SeriesColor.secondary),
                .init(label: "Compressed", value: Double(sample.compressed), color: SeriesColor.tertiary),
                .init(label: "Cached", value: Double(sample.cached), color: SeriesColor.neutral.opacity(0.5)),
            ], total: Double(sample.total))

            VStack(spacing: 6) {
                LegendRow(color: SeriesColor.primary, label: "App memory", value: Formatters.bytes(sample.appMemory))
                LegendRow(color: SeriesColor.secondary, label: "Wired", value: Formatters.bytes(sample.wired))
                LegendRow(color: SeriesColor.tertiary, label: "Compressed", value: Formatters.bytes(sample.compressed))
                LegendRow(color: SeriesColor.neutral.opacity(0.5), label: "Cached files", value: Formatters.bytes(sample.cached))
                Divider()
                LegendRow(color: .clear, label: "Swap used",
                          value: "\(Formatters.bytes(sample.swapUsed)) of \(Formatters.bytes(sample.swapTotal))")
            }
        }
    }
}

// MARK: - Network

struct NetworkCard: View {
    let sample: NetworkSample
    let history: [SeriesPoint]
    let window: ClosedRange<Date>

    private var activeInterfaces: [NetworkInterfaceSample] {
        Array(sample.interfaces.filter { $0.totalReceived + $0.totalSent > 0 }.prefix(4))
    }

    var body: some View {
        VitalCard(title: "Network", systemImage: "network") {
            HStack(spacing: 24) {
                StatValue(value: Formatters.rate(sample.downloadBytesPerSecond), caption: "Download", color: SeriesColor.primary)
                StatValue(value: Formatters.rate(sample.uploadBytesPerSecond), caption: "Upload", color: SeriesColor.secondary)
            }

            TwoSeriesChart(points: history, primaryLabel: "Download", secondaryLabel: "Upload",
                           style: .line, window: window,
                           yDomain: TwoSeriesChart.rateDomain(for: history),
                           format: Formatters.rate)

            if !activeInterfaces.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Interface")
                        Text("Down")
                        Text("Up")
                        Text("Total")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ForEach(activeInterfaces) { interface in
                        GridRow {
                            Text(interface.name).fontWeight(.medium)
                            Text(Formatters.rate(interface.downloadBytesPerSecond))
                            Text(Formatters.rate(interface.uploadBytesPerSecond))
                            Text(Formatters.bytes(interface.totalReceived + interface.totalSent))
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .monospacedDigit()
                    }
                }
            }
        }
    }
}

// MARK: - Disk

struct DiskCard: View {
    let sample: DiskSample
    let history: [SeriesPoint]
    let window: ClosedRange<Date>

    var body: some View {
        VitalCard(title: "Disk", systemImage: "internaldrive") {
            HStack(spacing: 24) {
                StatValue(value: Formatters.rate(sample.readBytesPerSecond), caption: "Read", color: SeriesColor.primary)
                StatValue(value: Formatters.rate(sample.writeBytesPerSecond), caption: "Write", color: SeriesColor.secondary)
            }

            TwoSeriesChart(points: history, primaryLabel: "Read", secondaryLabel: "Write",
                           style: .line, window: window,
                           yDomain: TwoSeriesChart.rateDomain(for: history),
                           format: Formatters.rate)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Startup disk")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Formatters.bytes(sample.used)) of \(Formatters.bytes(sample.capacity)) used")
                        .monospacedDigit()
                }
                .font(.callout)
                ProgressView(value: sample.usedFraction)
                    .tint(SeriesColor.primary)
            }
        }
    }
}

// MARK: - Temperature

struct TemperatureCard: View {
    let sample: TemperatureSample
    let thermalState: ProcessInfo.ThermalState

    @State private var showsAllSensors = false

    var body: some View {
        VitalCard(title: "Temperatures", systemImage: "thermometer.medium") {
            if sample.isAvailable {
                HStack(spacing: 24) {
                    if let cpu = sample.cpuAverage {
                        StatValue(value: Formatters.temperature(cpu), caption: "CPU average")
                    } else if let die = sample.dieAverage {
                        StatValue(value: Formatters.temperature(die), caption: "SoC die average")
                    }
                    if let gpu = sample.gpuAverage {
                        StatValue(value: Formatters.temperature(gpu), caption: "GPU average")
                    }
                    if let hottest = sample.hottest {
                        StatValue(value: Formatters.temperature(hottest.celsius), caption: "Hottest · \(hottest.name)")
                    }
                }

                VStack(spacing: 8) {
                    ForEach(sample.categories, id: \.self) { category in
                        if let maximum = sample.maximum(in: category) {
                            TemperatureRow(label: category.rawValue, celsius: maximum)
                        }
                    }
                }

                DisclosureGroup("All sensors (\(sample.readings.count))", isExpanded: $showsAllSensors) {
                    VStack(spacing: 4) {
                        ForEach(sample.readings.sorted { $0.celsius > $1.celsius }) { reading in
                            HStack {
                                Text(reading.name)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(Formatters.temperature(reading.celsius))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } else {
                Text("Sensor readings are unavailable. Temperature sensors require Apple silicon and the app must run without App Sandbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("System thermal state")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadge(text: thermalState.label, systemImage: "flame", color: thermalState.color)
            }
        }
    }
}

/// Label, thin bar scaled 0...110 °C, and a status word so the level isn't color-only.
struct TemperatureRow: View {
    let label: String
    let celsius: Double

    private var level: TemperatureLevel { TemperatureLevel(celsius: celsius) }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .frame(width: 110, alignment: .leading)
            ProgressView(value: min(celsius, 110), total: 110)
                .tint(level.color)
            Text(Formatters.temperature(celsius))
                .font(.callout)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            Label(level.label, systemImage: level.symbolName)
                .font(.caption)
                .foregroundStyle(level.color)
                .frame(width: 70, alignment: .leading)
        }
    }
}

// MARK: - System

struct SystemCard: View {
    let info: SystemInfo
    let snapshot: VitalsSnapshot

    var body: some View {
        VitalCard(title: "System", systemImage: "desktopcomputer") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("Chip", info.chipName)
                row("Cores", coresDescription)
                row("Memory", Formatters.bytes(snapshot.memory.total))
                row("macOS", info.osVersion)
                row("Uptime", Formatters.uptime(snapshot.uptime))
                row("Load average", loadDescription)
            }
            .font(.callout)
        }
    }

    private var coresDescription: String {
        if info.performanceCores > 0 || info.efficiencyCores > 0 {
            return "\(info.totalCores) (\(info.performanceCores) performance, \(info.efficiencyCores) efficiency)"
        }
        return "\(info.totalCores)"
    }

    private var loadDescription: String {
        guard snapshot.loadAverages.count == 3 else { return "—" }
        return snapshot.loadAverages
            .map { $0.formatted(.number.precision(.fractionLength(2))) }
            .joined(separator: "  ")
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
