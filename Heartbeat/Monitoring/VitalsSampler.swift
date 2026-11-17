//
//  VitalsSampler.swift
//  Heartbeat
//

import Foundation

/// Takes periodic snapshots of the machine's vitals off the main thread.
/// Keeps the previous raw counters so it can compute rates between calls.
actor VitalsSampler {
    private var previousTicks: [CPUTicks] = []
    private var previousInterfaces: [String: InterfaceCounters] = [:]
    private var previousDisk: DiskCounters?
    private var previousTimestamp: Date?
    private let temperatureReader = TemperatureReader()

    func sample() -> VitalsSnapshot {
        let now = Date()
        let elapsed = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0
        previousTimestamp = now

        let ticks = SystemProbe.cpuTicks()
        let cpu = Self.cpuSample(previous: previousTicks, current: ticks)
        previousTicks = ticks

        let interfaces = SystemProbe.interfaceCounters()
        let network = networkSample(current: interfaces, elapsed: elapsed)
        previousInterfaces = Dictionary(interfaces.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        let diskCounters = SystemProbe.diskCounters()
        let disk = diskSample(current: diskCounters, elapsed: elapsed)
        previousDisk = diskCounters

        return VitalsSnapshot(
            timestamp: now,
            cpu: cpu,
            memory: SystemProbe.memory(),
            network: network,
            disk: disk,
            temperatures: temperatureReader.read(),
            loadAverages: SystemProbe.loadAverages(),
            uptime: ProcessInfo.processInfo.systemUptime,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }

    // MARK: - Rate math

    private static func cpuSample(previous: [CPUTicks], current: [CPUTicks]) -> CPUSample {
        guard !current.isEmpty, previous.count == current.count else {
            return CPUSample(user: 0, system: 0, idle: 1, perCore: Array(repeating: 0, count: current.count))
        }

        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalIdle: Double = 0
        var totalAll: Double = 0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        for (old, new) in zip(previous, current) {
            // Tick counters are 32-bit and wrap, so subtract with wrapping arithmetic.
            let user = Double(new.user &- old.user) + Double(new.nice &- old.nice)
            let system = Double(new.system &- old.system)
            let idle = Double(new.idle &- old.idle)
            let total = user + system + idle
            perCore.append(total > 0 ? (user + system) / total : 0)
            totalUser += user
            totalSystem += system
            totalIdle += idle
            totalAll += total
        }

        guard totalAll > 0 else {
            return CPUSample(user: 0, system: 0, idle: 1, perCore: perCore)
        }
        return CPUSample(
            user: totalUser / totalAll,
            system: totalSystem / totalAll,
            idle: totalIdle / totalAll,
            perCore: perCore
        )
    }

    private func networkSample(current: [InterfaceCounters], elapsed: TimeInterval) -> NetworkSample {
        var samples: [NetworkInterfaceSample] = []
        var aggregateDown: Double = 0
        var aggregateUp: Double = 0

        for counters in current {
            var down: Double = 0
            var up: Double = 0
            if elapsed > 0, let old = previousInterfaces[counters.name] {
                down = Double(counters.received &- old.received) / elapsed
                up = Double(counters.sent &- old.sent) / elapsed
            }
            // Physical interfaces (Wi-Fi, Ethernet, Thunderbolt) are all en*. Tunnels and
            // peer-to-peer links ride on top of them, so only en* counts toward the total.
            if counters.name.hasPrefix("en") {
                aggregateDown += down
                aggregateUp += up
            }
            samples.append(NetworkInterfaceSample(
                name: counters.name,
                downloadBytesPerSecond: down,
                uploadBytesPerSecond: up,
                totalReceived: counters.received,
                totalSent: counters.sent
            ))
        }

        samples.sort { lhs, rhs in
            let lhsRate = lhs.downloadBytesPerSecond + lhs.uploadBytesPerSecond
            let rhsRate = rhs.downloadBytesPerSecond + rhs.uploadBytesPerSecond
            if lhsRate != rhsRate { return lhsRate > rhsRate }
            return (lhs.totalReceived + lhs.totalSent) > (rhs.totalReceived + rhs.totalSent)
        }
        return NetworkSample(downloadBytesPerSecond: aggregateDown, uploadBytesPerSecond: aggregateUp, interfaces: samples)
    }

    private func diskSample(current: DiskCounters, elapsed: TimeInterval) -> DiskSample {
        var read: Double = 0
        var write: Double = 0
        if elapsed > 0, let old = previousDisk {
            read = Double(current.read &- old.read) / elapsed
            write = Double(current.written &- old.written) / elapsed
        }
        let volume = SystemProbe.rootVolumeCapacity()
        return DiskSample(readBytesPerSecond: read, writeBytesPerSecond: write,
                          capacity: volume.capacity, available: volume.available)
    }
}
