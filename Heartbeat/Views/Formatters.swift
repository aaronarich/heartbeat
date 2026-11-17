//
//  Formatters.swift
//  Heartbeat
//

import Foundation
import SwiftUI

nonisolated enum Formatters {
    /// Memory and storage sizes, e.g. "24.2 GB".
    static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    /// Throughput, e.g. "12.4 MB/s".
    static func rate(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond.rounded()).formatted(.byteCount(style: .decimal, spellsOutZero: false)) + "/s"
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Sensors report Celsius; everything is displayed in Fahrenheit, e.g. "136°F".
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: .fahrenheit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Short form for the menu bar, e.g. "136°".
    static func temperatureCompact(_ celsius: Double) -> String {
        let fahrenheit = celsius * 9 / 5 + 32
        return "\(Int(fahrenheit.rounded()))°"
    }

    static func uptime(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated))
    }
}

/// Shared chart series colors. Blue and orange are the colorblind-safe pair; the
/// first series is always blue and the second always orange across every card.
enum SeriesColor {
    static let primary = Color.blue
    static let secondary = Color.orange
    static let tertiary = Color.purple
    static let neutral = Color.gray
}

extension TemperatureLevel {
    var color: Color {
        switch self {
        case .cool: .green
        case .warm: .yellow
        case .hot: .orange
        case .critical: .red
        }
    }
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        @unknown default: .gray
        }
    }
}
