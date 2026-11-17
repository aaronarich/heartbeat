//
//  Vitals.swift
//  Heartbeat
//

import Foundation

/// A single reading of every vital the dashboard shows. Produced by `VitalsSampler`.
nonisolated struct VitalsSnapshot: Sendable {
    var timestamp: Date
    var cpu: CPUSample
    var memory: MemorySample
    var network: NetworkSample
    var disk: DiskSample
    var temperatures: TemperatureSample
    /// 1, 5 and 15 minute load averages.
    var loadAverages: [Double]
    var uptime: TimeInterval
    var thermalState: ProcessInfo.ThermalState
}

// MARK: - CPU

nonisolated struct CPUSample: Sendable {
    /// Fractions in 0...1 of total CPU time across all cores.
    var user: Double
    var system: Double
    var idle: Double
    /// Busy fraction (0...1) for each logical core, in kernel order.
    var perCore: [Double]

    var busy: Double { user + system }

    static let zero = CPUSample(user: 0, system: 0, idle: 1, perCore: [])
}

// MARK: - Memory

nonisolated enum MemoryPressure: String, Sendable {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

nonisolated struct MemorySample: Sendable {
    var total: UInt64
    /// Memory used by apps, excluding purgeable pages.
    var appMemory: UInt64
    var wired: UInt64
    var compressed: UInt64
    /// File-backed and purgeable pages that can be reclaimed cheaply.
    var cached: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure

    /// Matches Activity Monitor's "Memory Used": app + wired + compressed.
    var used: UInt64 { appMemory + wired + compressed }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

// MARK: - Network

nonisolated struct NetworkInterfaceSample: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    var totalReceived: UInt64
    var totalSent: UInt64
}

nonisolated struct NetworkSample: Sendable {
    /// Aggregate over physical interfaces (en*), so VPN tunnels are not double counted.
    var downloadBytesPerSecond: Double
    var uploadBytesPerSecond: Double
    var interfaces: [NetworkInterfaceSample]
}

// MARK: - Disk

nonisolated struct DiskSample: Sendable {
    var readBytesPerSecond: Double
    var writeBytesPerSecond: Double
    var capacity: UInt64
    var available: UInt64

    var used: UInt64 { capacity > available ? capacity - available : 0 }
    var usedFraction: Double { capacity == 0 ? 0 : Double(used) / Double(capacity) }
}

// MARK: - Temperature

nonisolated enum TemperatureCategory: String, CaseIterable, Sendable {
    case cpuPerformance = "CPU P-cores"
    case cpuEfficiency = "CPU E-cores"
    case gpu = "GPU"
    case soc = "SoC die"
    case neuralEngine = "Neural Engine"
    case storage = "Storage"
    case battery = "Battery"
    case power = "Power / PMU"
    case other = "Other"

    /// Buckets an Apple silicon HID sensor name (e.g. "pACC MTR Temp Sensor3") into a category.
    static func classify(_ name: String) -> TemperatureCategory {
        let lower = name.lowercased()
        if lower.contains("pacc") { return .cpuPerformance }
        if lower.contains("eacc") { return .cpuEfficiency }
        if lower.contains("gpu") { return .gpu }
        if lower.contains("ane") { return .neuralEngine }
        // M3/M4-class chips expose die temperatures as "PMU tdieN" with no per-cluster names.
        if lower.contains("tdie") || lower.contains("soc") { return .soc }
        if lower.contains("nand") || lower.contains("ssd") { return .storage }
        if lower.contains("battery") || lower.contains("gas gauge") { return .battery }
        if lower.contains("pmu") || lower.contains("tdev") { return .power }
        return .other
    }
}

nonisolated struct TemperatureReading: Sendable, Identifiable {
    var id: String
    var name: String
    var category: TemperatureCategory
    var celsius: Double
}

nonisolated struct TemperatureSample: Sendable {
    var readings: [TemperatureReading]
    /// False when the HID temperature services could not be opened on this machine.
    var isAvailable: Bool

    var cpuAverage: Double? { average(of: [.cpuPerformance, .cpuEfficiency]) }
    var gpuAverage: Double? { average(of: [.gpu]) }
    /// Average across SoC die sensors; the best CPU proxy on chips without per-cluster sensors.
    var dieAverage: Double? { average(of: [.soc]) }
    var hottest: TemperatureReading? { readings.max { $0.celsius < $1.celsius } }

    /// Categories that have at least one reading, in declaration order.
    var categories: [TemperatureCategory] {
        TemperatureCategory.allCases.filter { category in
            readings.contains { $0.category == category }
        }
    }

    func average(of categories: Set<TemperatureCategory>) -> Double? {
        let values = readings.filter { categories.contains($0.category) }.map(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    func maximum(in category: TemperatureCategory) -> Double? {
        readings.filter { $0.category == category }.map(\.celsius).max()
    }

    static let unavailable = TemperatureSample(readings: [], isAvailable: false)
}

nonisolated enum TemperatureLevel: Sendable {
    case cool, warm, hot, critical

    init(celsius: Double) {
        switch celsius {
        case ..<60: self = .cool
        case ..<80: self = .warm
        case ..<95: self = .hot
        default: self = .critical
        }
    }

    var label: String {
        switch self {
        case .cool: "Cool"
        case .warm: "Warm"
        case .hot: "Hot"
        case .critical: "Critical"
        }
    }

    var symbolName: String {
        switch self {
        case .cool: "thermometer.low"
        case .warm: "thermometer.medium"
        case .hot: "thermometer.high"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Static system info

nonisolated struct SystemInfo: Sendable {
    var chipName: String
    var performanceCores: Int
    var efficiencyCores: Int
    var totalCores: Int
    var osVersion: String
}

// MARK: - Chart history

/// One point of a two-series time chart (user/system, download/upload, read/write).
nonisolated struct SeriesPoint: Sendable, Identifiable {
    var id: Date { date }
    var date: Date
    var primary: Double
    var secondary: Double
}
