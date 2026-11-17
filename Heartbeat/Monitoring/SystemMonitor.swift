//
//  SystemMonitor.swift
//  Heartbeat
//

import Foundation
import Observation

/// Main-actor model the dashboard observes. Drives the sampler on a timer and
/// keeps a rolling window of history for the charts.
@Observable
final class SystemMonitor {
    private(set) var snapshot: VitalsSnapshot?
    private(set) var cpuHistory: [SeriesPoint] = []
    private(set) var networkHistory: [SeriesPoint] = []
    private(set) var diskHistory: [SeriesPoint] = []

    var refreshInterval: Duration = .seconds(1)
    /// How much history the charts show, in seconds.
    let historyWindow: TimeInterval = 60
    let systemInfo: SystemInfo

    private let sampler = VitalsSampler()
    private var samplingTask: Task<Void, Never>?

    init() {
        systemInfo = SystemProbe.systemInfo()
        start()
    }

#if DEBUG
    /// Preview-only: shows a fixed snapshot and never samples.
    init(previewSnapshot: VitalsSnapshot, info: SystemInfo) {
        systemInfo = info
        snapshot = previewSnapshot
    }
#endif

    /// Begins sampling in the background. Safe to call more than once.
    func start() {
        guard samplingTask == nil else { return }
        samplingTask = Task { await run() }
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    /// The x-axis range for the charts, ending at the latest snapshot.
    var chartWindow: ClosedRange<Date> {
        let end = snapshot?.timestamp ?? Date()
        return end.addingTimeInterval(-historyWindow)...end
    }

    /// Samples forever until the owning task is cancelled.
    private func run() async {
        // Rates need two readings, so take a throwaway first sample.
        _ = await sampler.sample()
        try? await Task.sleep(for: .milliseconds(500))

        while !Task.isCancelled {
            let snapshot = await sampler.sample()
            apply(snapshot)
            try? await Task.sleep(for: refreshInterval)
        }
    }

    private func apply(_ snapshot: VitalsSnapshot) {
        self.snapshot = snapshot
        let date = snapshot.timestamp

        cpuHistory.append(SeriesPoint(date: date, primary: snapshot.cpu.user * 100, secondary: snapshot.cpu.system * 100))
        networkHistory.append(SeriesPoint(date: date, primary: snapshot.network.downloadBytesPerSecond, secondary: snapshot.network.uploadBytesPerSecond))
        diskHistory.append(SeriesPoint(date: date, primary: snapshot.disk.readBytesPerSecond, secondary: snapshot.disk.writeBytesPerSecond))

        // Keep a little more than the visible window so the left edge stays connected.
        let cutoff = date.addingTimeInterval(-(historyWindow + 5))
        cpuHistory.removeAll { $0.date < cutoff }
        networkHistory.removeAll { $0.date < cutoff }
        diskHistory.removeAll { $0.date < cutoff }
    }
}
