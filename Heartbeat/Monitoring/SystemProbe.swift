//
//  SystemProbe.swift
//  Heartbeat
//
//  Low-level, stateless readers for kernel and IOKit counters. Each function
//  returns raw cumulative values; `VitalsSampler` turns them into rates.
//

import Foundation
import IOKit

/// Cumulative CPU ticks for one logical core, as reported by `host_processor_info`.
nonisolated struct CPUTicks: Sendable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

/// Cumulative byte counters for one network interface.
nonisolated struct InterfaceCounters: Sendable {
    var name: String
    var received: UInt64
    var sent: UInt64
}

/// Cumulative byte counters summed across all block storage drivers.
nonisolated struct DiskCounters: Sendable {
    var read: UInt64
    var written: UInt64
}

nonisolated enum SystemProbe {
    /// A single send right to the host port, reused so we don't leak one per call.
    private static let hostPort: host_t = mach_host_self()

    // MARK: CPU

    static func cpuTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            let byteCount = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), byteCount)
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    // MARK: Memory

    static func memory() -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = Sysctl.value("hw.memsize", as: UInt64.self) ?? 0
        let swap = Sysctl.value("vm.swapusage", as: xsw_usage.self)
        let pressureLevel = Sysctl.value("kern.memorystatus_vm_pressure_level", as: Int32.self) ?? 1
        let pressure: MemoryPressure = switch pressureLevel {
        case 4: .critical
        case 2: .warning
        default: .normal
        }

        guard result == KERN_SUCCESS else {
            return MemorySample(total: total, appMemory: 0, wired: 0, compressed: 0, cached: 0,
                                swapUsed: swap?.xsu_used ?? 0, swapTotal: swap?.xsu_total ?? 0, pressure: pressure)
        }

        // Same accounting Activity Monitor uses.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appMemory = internalPages > purgeable ? (internalPages - purgeable) * pageSize : 0
        let cached = (UInt64(stats.external_page_count) + purgeable) * pageSize

        return MemorySample(
            total: total,
            appMemory: appMemory,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            cached: cached,
            swapUsed: swap?.xsu_used ?? 0,
            swapTotal: swap?.xsu_total ?? 0,
            pressure: pressure
        )
    }

    // MARK: Network

    /// Reads 64-bit interface byte counters via the routing socket so they don't wrap at 4 GB.
    static func interfaceCounters() -> [InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [] }

        var results: [InterfaceCounters] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                defer { offset += messageLength }

                guard Int32(header.ifm_type) == RTM_IFINFO2,
                      offset + MemoryLayout<if_msghdr2>.size <= length else { continue }
                let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                let flags = message.ifm_flags
                guard flags & IFF_LOOPBACK == 0, flags & IFF_UP != 0 else { continue }

                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                guard if_indextoname(UInt32(message.ifm_index), &nameBuffer) != nil else { continue }
                let name = String(decoding: nameBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)

                results.append(InterfaceCounters(
                    name: name,
                    received: message.ifm_data.ifi_ibytes,
                    sent: message.ifm_data.ifi_obytes
                ))
            }
        }
        return results
    }

    // MARK: Disk

    static func diskCounters() -> DiskCounters {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return DiskCounters(read: 0, written: 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var written: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any],
               let statistics = dictionary["Statistics"] as? [String: Any] {
                read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return DiskCounters(read: read, written: written)
    }

    static func rootVolumeCapacity() -> (capacity: UInt64, available: UInt64) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return (0, 0) }
        let capacity = UInt64(values.volumeTotalCapacity ?? 0)
        let available = UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0))
        return (capacity, available)
    }

    // MARK: Misc

    static func loadAverages() -> [Double] {
        var averages = [Double](repeating: 0, count: 3)
        let count = getloadavg(&averages, 3)
        return count == 3 ? averages : []
    }

    static func systemInfo() -> SystemInfo {
        let total = Int(Sysctl.value("hw.ncpu", as: Int32.self) ?? 0)
        let performance = Int(Sysctl.value("hw.perflevel0.physicalcpu", as: Int32.self) ?? 0)
        let efficiency = Int(Sysctl.value("hw.perflevel1.physicalcpu", as: Int32.self) ?? 0)
        return SystemInfo(
            chipName: Sysctl.string("machdep.cpu.brand_string") ?? "Unknown",
            performanceCores: performance,
            efficiencyCores: efficiency,
            totalCores: total,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

// MARK: - sysctl helpers

nonisolated enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// Reads a fixed-size, trivially copyable value such as `UInt64`, `Int32` or a C struct.
    static func value<T>(_ name: String, as type: T.Type) -> T? {
        var size = MemoryLayout<T>.size
        let storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<T>.alignment)
        defer { storage.deallocate() }
        guard sysctlbyname(name, storage, &size, nil, 0) == 0 else { return nil }
        return storage.load(as: T.self)
    }
}
