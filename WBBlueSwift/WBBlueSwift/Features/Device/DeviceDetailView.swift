//
//  DeviceDetailView.swift
//  WBBlueSwift
//
//  设备详情:连接状态条(重连状态机可视化)、服务浏览器、
//  特征读写/订阅、RSSI,以及心率/私有协议两个专题页入口。
//

import CoreBluetooth
import SwiftUI

struct DeviceDetailView: View {

    private let central: any BLECentral
    @State private var model: DeviceDetailViewModel
    @State private var writeTarget: GATTCharacteristic?

    init(central: any BLECentral, device: DiscoveredDevice) {
        self.central = central
        _model = State(initialValue: DeviceDetailViewModel(central: central, device: device))
    }

    var body: some View {
        List {
            connectionSection

            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if model.orchestrator.phase == .connected {
                featureSection
            }

            ForEach(model.services) { service in
                Section {
                    ForEach(service.characteristics) { characteristic in
                        CharacteristicRow(
                            characteristic: characteristic,
                            latestValue: model.latestValues[characteristic.uuid.uuidString],
                            isNotifying: model.notifyingCharacteristics.contains(characteristic.uuid.uuidString),
                            onRead: { Task { await model.read(characteristic.uuid) } },
                            onWrite: { writeTarget = characteristic },
                            onToggleNotify: { Task { await model.toggleNotify(characteristic.uuid) } }
                        )
                    }
                } header: {
                    Text(BLEConstants.displayName(for: service.uuid))
                }
            }
        }
        .navigationTitle(model.device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $writeTarget) { characteristic in
            WriteSheet(characteristic: characteristic) { hex, withResponse in
                await model.write(characteristic.uuid, hex: hex, withResponse: withResponse)
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.teardown() }
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 10, height: 10)
                Text(model.orchestrator.phase.text)
                Spacer()
                if let rssi = model.rssi {
                    Button("\(rssi) dBm") {
                        Task { await model.refreshRSSI() }
                    }
                    .font(.caption.monospacedDigit())
                }
            }
            if case .failed = model.orchestrator.phase {
                Button("重新连接") { model.start() }
            }
        } footer: {
            Text("意外断连会按指数退避自动重连;离开本页视为主动断开。")
        }
    }

    private var featureSection: some View {
        Section("专题演示") {
            if model.hasHeartRate {
                NavigationLink("实时心率(订阅 + 图表)") {
                    HeartRateView(central: central, deviceID: model.device.id)
                }
            }
            if model.hasCustomProtocol {
                NavigationLink("私有协议控制台(帧 + 分包)") {
                    ProtocolConsoleView(central: central, deviceID: model.device.id)
                }
            }
        }
    }

    private var phaseColor: Color {
        switch model.orchestrator.phase {
        case .connected: .green
        case .connecting, .waitingRetry: .orange
        case .idle: .gray
        case .failed: .red
        }
    }
}

/// 单条特征:短名、属性徽标、最近值、读/写/订阅操作。
struct CharacteristicRow: View {
    let characteristic: GATTCharacteristic
    let latestValue: Data?
    let isNotifying: Bool
    let onRead: () -> Void
    let onWrite: () -> Void
    let onToggleNotify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BLEConstants.name(for: characteristic.uuid) ?? characteristic.uuid.uuidString)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 4) {
                ForEach(characteristic.propertyBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }

            if let value = latestValue ?? characteristic.value, !value.isEmpty {
                Text(valueText(value))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                if characteristic.properties.contains(.read) {
                    Button("读取", action: onRead)
                }
                if characteristic.properties.contains(.write)
                    || characteristic.properties.contains(.writeWithoutResponse) {
                    Button("写入", action: onWrite)
                }
                if characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) {
                    Button(isNotifying ? "关闭通知" : "订阅通知", action: onToggleNotify)
                        .foregroundStyle(isNotifying ? .orange : .accentColor)
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    private func valueText(_ value: Data) -> String {
        var text = "HEX \(value.hexString(separator: " "))"
        if let string = String(data: value, encoding: .utf8),
           string.allSatisfy({ !$0.isASCII || ($0.asciiValue ?? 0) >= 0x20 }) {
            text += "  |  \"\(string)\""
        }
        return text
    }
}

/// hex 写入面板:withResponse / withoutResponse 二选一。
private struct WriteSheet: View {
    let characteristic: GATTCharacteristic
    let onSend: (String, Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var hexText = ""
    @State private var withResponse = true
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                Section("十六进制数据") {
                    TextField("如:A5 5A 01 00 00 00", text: $hexText)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    if characteristic.properties.contains(.write) {
                        Toggle("有响应写(Write Request)", isOn: $withResponse)
                            .disabled(!characteristic.properties.contains(.writeWithoutResponse))
                    }
                } footer: {
                    Text("有响应写可靠但慢(一来一回);免响应写吞吐高,靠上层协议保证可靠性。")
                }
                Button {
                    Task {
                        sending = true
                        let ok = await onSend(hexText, effectiveWithResponse)
                        sending = false
                        if ok { dismiss() }
                    }
                } label: {
                    HStack {
                        Text("发送")
                        if sending { Spacer(); ProgressView() }
                    }
                }
                .disabled(hexText.isEmpty || sending)
            }
            .navigationTitle("写入 \(BLEConstants.name(for: characteristic.uuid) ?? characteristic.uuid.uuidString)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("取消") { dismiss() }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            withResponse = characteristic.properties.contains(.write)
        }
    }

    private var effectiveWithResponse: Bool {
        characteristic.properties.contains(.write) && withResponse
    }
}
