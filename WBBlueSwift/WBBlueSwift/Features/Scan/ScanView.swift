//
//  ScanView.swift
//  WBBlueSwift
//
//  扫描页:蓝牙状态横幅(异常引导)、扫描控制、设备列表(RSSI/广播解析)。
//

import CoreBluetooth
import SwiftUI

struct ScanView: View {

    @Environment(AppModel.self) private var app
    @State private var model: ScanViewModel
    @State private var showSettings = false

    init(central: any BLECentral) {
        _model = State(initialValue: ScanViewModel(central: central))
    }

    var body: some View {
        List {
            if let error = model.state.asError {
                Section {
                    StateBanner(error: error)
                }
            }

            Section {
                Toggle("只扫心率设备(服务过滤 0x180D)", isOn: Binding(
                    get: { model.filterHeartRateOnly },
                    set: { model.filterHeartRateOnly = $0 }
                ))
                .disabled(model.isScanning)

                Button {
                    model.toggleScan()
                } label: {
                    HStack {
                        Text(model.isScanning ? "停止扫描" : "开始扫描(20s 自停)")
                        if model.isScanning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.state != .poweredOn)
            } footer: {
                Text("蓝牙状态:\(model.state.rawValue)")
            }

            Section("发现的设备(\(model.devices.count))") {
                if model.devices.isEmpty {
                    Text(model.isScanning ? "正在搜索…" : "尚无设备,点上方开始扫描")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.devices) { device in
                    NavigationLink(value: device) {
                        DeviceRow(device: device)
                    }
                }
            }
        }
        .navigationTitle("设备扫描")
        .toolbar {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .navigationDestination(for: DiscoveredDevice.self) { device in
            DeviceDetailView(central: app.central, device: device)
                .onAppear { model.stopScan() }  // 连接前停扫:省电且加快建连
        }
        .task { await model.observeState() }
        .onDisappear { model.stopScan() }
    }
}

/// 蓝牙不可用时的引导横幅(异常处理 UI 落点)。
private struct StateBanner: View {
    let error: BLEError

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.errorDescription ?? "蓝牙不可用", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if case .unauthorized = error {
                Button("打开设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.displayName)
                    .font(.headline)
                Spacer()
                SignalIcon(rssi: device.rssi)
                Text("\(device.rssi) dBm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !device.advertisedServices.isEmpty {
                Text("广播服务:" + device.advertisedServices
                    .map { BLEConstants.name(for: $0) ?? $0.uuidString }
                    .joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let manufacturerData = device.manufacturerData {
                Text("厂商数据:\(manufacturerData.hexString(separator: " "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SignalIcon: View {
    let rssi: Int

    var body: some View {
        Image(systemName: "cellularbars", variableValue: strength)
            .foregroundStyle(strength > 0.5 ? .green : .orange)
    }

    /// 经验映射:-40 很近 … -90 很远。
    private var strength: Double {
        max(0, min(1, (Double(rssi) + 90) / 50))
    }
}

/// 数据源与故障注入设置。
private struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Toggle("使用 Mock 数据源", isOn: $app.useMock)
                } footer: {
                    Text("模拟器无蓝牙硬件,只能用 Mock;真机可切换真实 CoreBluetooth。切换会重建所有页面。")
                }
                if app.useMock {
                    Section("故障注入(演示异常处理)") {
                        Toggle("连接一直超时", isOn: $app.simulateConnectFailure)
                        Toggle("连上 15 秒强制断连(看自动重连)", isOn: $app.simulateRandomDrop)
                    }
                }
            }
            .navigationTitle("设置")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
        .presentationDetents([.medium])
    }
}
