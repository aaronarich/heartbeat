//
//  DashboardPreview.swift
//  Heartbeat
//
//  Fixed sample data so the dashboard can be previewed without live sampling.
//

import SwiftUI

#if DEBUG
enum PreviewData {
    static let now = Date()
    static let window: ClosedRange<Date> = now.addingTimeInterval(-60)...now

    static let info = SystemInfo(chipName: "Apple M4 Pro", performanceCores: 10, efficiencyCores: 4,
                                 totalCores: 14, osVersion: "Version 27.2.1 (Build 26B131)")

    static let snapshot = VitalsSnapshot(
        timestamp: now,
        cpu: CPUSample(user: 0.23, system: 0.08, idle: 0.69,
                       perCore: [0.6, 0.5, 0.4, 0.3, 0.8, 0.2, 0.1, 0.05, 0.3, 0.9, 0.15, 0.1, 0.2, 0.4]),
        memory: MemorySample(total: 24 << 30, appMemory: 11 << 30, wired: 3 << 30, compressed: 2 << 30,
                             cached: 5 << 30, swapUsed: 512 << 20, swapTotal: 2 << 30, pressure: .normal),
        network: NetworkSample(downloadBytesPerSecond: 3_400_000, uploadBytesPerSecond: 420_000, interfaces: [
            NetworkInterfaceSample(name: "en0", downloadBytesPerSecond: 3_400_000, uploadBytesPerSecond: 420_000,
                                   totalReceived: 962_144_256, totalSent: 118_999_040),
            NetworkInterfaceSample(name: "utun2", downloadBytesPerSecond: 12_000, uploadBytesPerSecond: 3_000,
                                   totalReceived: 49_591_296, totalSent: 8_134_656),
        ]),
        disk: DiskSample(readBytesPerSecond: 18_000_000, writeBytesPerSecond: 6_000_000,
                         capacity: 1_000 << 30, available: 410 << 30),
        temperatures: TemperatureSample(readings: [
            TemperatureReading(id: "PMU tdie1", name: "PMU tdie1", category: .soc, celsius: 55.4),
            TemperatureReading(id: "PMU tdie8", name: "PMU tdie8", category: .soc, celsius: 61.2),
            TemperatureReading(id: "GPU MTR Temp Sensor1", name: "GPU MTR Temp Sensor1", category: .gpu, celsius: 48.0),
            TemperatureReading(id: "NAND CH0 temp", name: "NAND CH0 temp", category: .storage, celsius: 34.0),
            TemperatureReading(id: "gas gauge battery", name: "gas gauge battery", category: .battery, celsius: 29.6),
        ], isAvailable: true),
        loadAverages: [2.31, 2.02, 1.87],
        uptime: 3 * 86_400 + 5 * 3_600 + 12 * 60,
        thermalState: .nominal
    )

    static func history(scale: Double, secondaryScale: Double) -> [SeriesPoint] {
        (0..<60).map { index in
            let t = Double(index)
            return SeriesPoint(date: now.addingTimeInterval(t - 59),
                               primary: scale * (0.5 + 0.4 * sin(t / 6)),
                               secondary: secondaryScale * (0.5 + 0.4 * cos(t / 9)))
        }
    }
}

#Preview("Dashboard") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 620), spacing: 16, alignment: .top)],
                  alignment: .leading, spacing: 16) {
            CPUCard(sample: PreviewData.snapshot.cpu, history: PreviewData.history(scale: 60, secondaryScale: 20),
                    window: PreviewData.window, info: PreviewData.info)
            MemoryCard(sample: PreviewData.snapshot.memory)
            NetworkCard(sample: PreviewData.snapshot.network,
                        history: PreviewData.history(scale: 4_000_000, secondaryScale: 600_000),
                        window: PreviewData.window)
            DiskCard(sample: PreviewData.snapshot.disk,
                     history: PreviewData.history(scale: 20_000_000, secondaryScale: 8_000_000),
                     window: PreviewData.window)
            TemperatureCard(sample: PreviewData.snapshot.temperatures, thermalState: .nominal)
            SystemCard(info: PreviewData.info, snapshot: PreviewData.snapshot)
        }
        .padding(20)
    }
    .frame(width: 1160, height: 820)
}
#endif
