//
//  ContentView.swift
//  Heartbeat
//
//  Created by Aaron A. Rich on 11/17/26.
//

import SwiftUI

/// The full dashboard window. Reads the shared `SystemMonitor` from the environment.
struct ContentView: View {
    @Environment(SystemMonitor.self) private var monitor

    private let columns = [
        GridItem(.adaptive(minimum: 340, maximum: 620), spacing: 16, alignment: .top)
    ]

    var body: some View {
        @Bindable var monitor = monitor

        Group {
            if let snapshot = monitor.snapshot {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        CPUCard(sample: snapshot.cpu, history: monitor.cpuHistory,
                                window: monitor.chartWindow, info: monitor.systemInfo)
                        MemoryCard(sample: snapshot.memory)
                        NetworkCard(sample: snapshot.network, history: monitor.networkHistory,
                                    window: monitor.chartWindow)
                        DiskCard(sample: snapshot.disk, history: monitor.diskHistory,
                                 window: monitor.chartWindow)
                        TemperatureCard(sample: snapshot.temperatures, thermalState: snapshot.thermalState)
                        SystemCard(info: monitor.systemInfo, snapshot: snapshot)
                    }
                    .padding(20)
                }
            } else {
                ProgressView("Reading vitals…")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("Heartbeat")
        .toolbar {
            ToolbarItem {
                Picker("Refresh", selection: $monitor.refreshInterval) {
                    Text("0.5 s").tag(Duration.milliseconds(500))
                    Text("1 s").tag(Duration.seconds(1))
                    Text("2 s").tag(Duration.seconds(2))
                    Text("5 s").tag(Duration.seconds(5))
                }
                .pickerStyle(.menu)
                .help("How often to sample the system")
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SystemMonitor())
}
