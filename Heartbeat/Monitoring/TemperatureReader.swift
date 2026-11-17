//
//  TemperatureReader.swift
//  Heartbeat
//
//  Reads Apple silicon temperature sensors through the IOKit HID event system.
//  These entry points are not in any public header, so they are declared here by
//  symbol name. They are the same calls used by most third-party Mac monitors.
//

import Foundation
import IOKit
import IOKit.hid

@_silgen_name("IOHIDEventSystemClientCreate")
nonisolated private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
nonisolated private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary)

@_silgen_name("IOHIDEventSystemClientCopyServices")
nonisolated private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
nonisolated private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
nonisolated private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDEventGetFloatValue")
nonisolated private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: UInt32) -> Double

/// Owns a HID event system client and the list of temperature services it matched.
/// Create once and call `read()` on every tick.
nonisolated final class TemperatureReader {
    private struct Sensor {
        let name: String
        let category: TemperatureCategory
        let service: CFTypeRef
    }

    // kHIDPage_AppleVendor / kHIDUsage_AppleVendor_TemperatureSensor
    private static let appleVendorUsagePage = 0xff00
    private static let temperatureSensorUsage = 5
    // kIOHIDEventTypeTemperature and its base field (type << 16).
    private static let temperatureEventType: Int64 = 15
    private static let temperatureField: UInt32 = 15 << 16

    private let client: CFTypeRef?
    private let sensors: [Sensor]

    var isAvailable: Bool { !sensors.isEmpty }

    init() {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            self.client = nil
            self.sensors = []
            return
        }
        self.client = client

        let matching: [String: Int] = [
            "PrimaryUsagePage": Self.appleVendorUsagePage,
            "PrimaryUsage": Self.temperatureSensorUsage,
        ]
        IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

        guard let servicesRef = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() else {
            self.sensors = []
            return
        }
        let services = (servicesRef as NSArray) as [AnyObject]

        var sensors: [Sensor] = []
        for service in services {
            guard let name = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?.takeRetainedValue() as? String else {
                continue
            }
            // Calibration channels report nonsense temperatures.
            if name.lowercased().contains("tcal") { continue }
            sensors.append(Sensor(
                name: name,
                category: TemperatureCategory.classify(name),
                service: service
            ))
        }
        self.sensors = sensors
    }

    func read() -> TemperatureSample {
        guard isAvailable else { return .unavailable }

        // The HID system often lists the same physical sensor several times, so
        // average the valid values for each name and keep first-seen order.
        var order: [String] = []
        var sums: [String: (total: Double, count: Int, category: TemperatureCategory)] = [:]
        for sensor in sensors {
            guard let event = IOHIDServiceClientCopyEvent(sensor.service, Self.temperatureEventType, 0, 0)?.takeRetainedValue() else {
                continue
            }
            let celsius = IOHIDEventGetFloatValue(event, Self.temperatureField)
            // Drop disconnected or implausible sensors.
            guard celsius > 0, celsius < 150 else { continue }
            if var existing = sums[sensor.name] {
                existing.total += celsius
                existing.count += 1
                sums[sensor.name] = existing
            } else {
                order.append(sensor.name)
                sums[sensor.name] = (celsius, 1, sensor.category)
            }
        }

        let readings = order.compactMap { name -> TemperatureReading? in
            guard let entry = sums[name] else { return nil }
            return TemperatureReading(id: name, name: name, category: entry.category,
                                      celsius: entry.total / Double(entry.count))
        }
        return TemperatureSample(readings: readings, isAvailable: true)
    }
}
