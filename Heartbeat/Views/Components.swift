//
//  Components.swift
//  Heartbeat
//

import SwiftUI
import Charts

/// Rounded card container used by every dashboard tile.
struct VitalCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}

/// A big headline value with a small caption underneath.
struct StatValue: View {
    let value: String
    let caption: String
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Small status pill with icon and text so state is never conveyed by color alone.
struct StatusBadge: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Horizontal bar split into labeled segments with a 2pt gap between them.
struct SegmentedBar: View {
    struct Segment: Identifiable {
        var id: String { label }
        let label: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let total: Double

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    let fraction = total > 0 ? segment.value / total : 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: max(0, geometry.size.width * fraction - 2))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// Legend row: colored dot, name, and a right-aligned value.
struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.callout)
    }
}

/// Two-series time chart with a hover crosshair and tooltip.
struct TwoSeriesChart: View {
    enum Style {
        case stackedArea
        case line
    }

    let points: [SeriesPoint]
    let primaryLabel: String
    let secondaryLabel: String
    let style: Style
    let window: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let format: (Double) -> String

    @State private var selection: Date?

    private var selectedPoint: SeriesPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                if style == .stackedArea {
                    AreaMark(x: .value("Time", point.date), y: .value(primaryLabel, point.primary),
                             series: .value("Series", primaryLabel), stacking: .standard)
                        .foregroundStyle(by: .value("Series", primaryLabel))
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Time", point.date), y: .value(secondaryLabel, point.secondary),
                             series: .value("Series", secondaryLabel), stacking: .standard)
                        .foregroundStyle(by: .value("Series", secondaryLabel))
                        .interpolationMethod(.monotone)
                } else {
                    LineMark(x: .value("Time", point.date), y: .value(primaryLabel, point.primary),
                             series: .value("Series", primaryLabel))
                        .foregroundStyle(by: .value("Series", primaryLabel))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.date), y: .value(secondaryLabel, point.secondary),
                             series: .value("Series", secondaryLabel))
                        .foregroundStyle(by: .value("Series", secondaryLabel))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Time", selected.date))
                    .foregroundStyle(.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .topLeading, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(for: selected)
                    }
            }
        }
        .chartForegroundStyleScale([primaryLabel: SeriesColor.primary, secondaryLabel: SeriesColor.secondary])
        .chartXSelection(value: $selection)
        .chartXScale(domain: window)
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(format(number))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 8)
        .frame(height: 130)
    }

    private func tooltip(for point: SeriesPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.date, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Circle().fill(SeriesColor.primary).frame(width: 6, height: 6)
                Text(primaryLabel)
                Text(format(point.primary)).monospacedDigit()
            }
            HStack(spacing: 5) {
                Circle().fill(SeriesColor.secondary).frame(width: 6, height: 6)
                Text(secondaryLabel)
                Text(format(point.secondary)).monospacedDigit()
            }
        }
        .font(.caption)
        .padding(6)
        .background(.background, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

extension TwoSeriesChart {
    /// Y domain for throughput charts: zero to a bit above the peak, never below 1 KB/s.
    static func rateDomain(for points: [SeriesPoint]) -> ClosedRange<Double> {
        let peak = points.map { max($0.primary, $0.secondary) }.max() ?? 0
        return 0...max(peak * 1.15, 1_000)
    }
}
