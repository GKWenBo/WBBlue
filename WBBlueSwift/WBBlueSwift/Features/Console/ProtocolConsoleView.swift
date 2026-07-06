//
//  ProtocolConsoleView.swift
//  WBBlueSwift
//
//  私有协议控制台:走 FFF1 数据通道,下行命令帧、上行响应帧。
//  完整演示企业协议栈:构帧 → 按 MTU 分包写 → 通知分片到达 → 组包 → 解析。
//

import CoreBluetooth
import Foundation
import SwiftUI

@Observable
final class ProtocolConsoleViewModel {

    struct Line: Identifiable {
        enum Direction {
            case tx, rx, event
        }
        let id = UUID()
        let direction: Direction
        let text: String
        let detail: String?
    }

    private let central: any BLECentral
    private let deviceID: UUID
    private var assembler = PacketAssembler()
    private var seq: UInt8 = 0

    var transcript: [Line] = []
    var errorMessage: String?

    init(central: any BLECentral, deviceID: UUID) {
        self.central = central
        self.deviceID = deviceID
    }

    /// 订阅数据通道上行:分片 → 组包 → 帧解析。
    func run() async {
        do {
            let stream = try await central.notifications(
                id: deviceID, characteristic: BLEConstants.customData
            )
            append(.event, "已订阅数据通道 FFF1")
            for try await chunk in stream {
                append(.event, "↓ 收到分片 \(chunk.count)B", detail: chunk.hexString(separator: " "))
                for event in assembler.feed(chunk) {
                    switch event {
                    case .packet(let packet):
                        append(.rx, describe(packet), detail: payloadText(packet.payload))
                    case .error(let error):
                        append(.event, "⚠️ 坏帧丢弃:\(error)")
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 构帧并按协商 MTU 分包下行。
    func send(cmd: UInt8, payload: Data, label: String) async {
        seq &+= 1
        let frame = PacketCodec.encode(Packet(cmd: cmd, seq: seq, payload: payload))
        let mtu = central.maximumWriteLength(id: deviceID, withResponse: true)
        let chunks = PacketCodec.chunks(of: frame, mtuPayload: mtu)
        do {
            for chunk in chunks {
                try await central.writeValue(
                    id: deviceID, characteristic: BLEConstants.customData,
                    data: chunk, withResponse: true
                )
            }
            append(.tx, "\(label) cmd=0x\(String(format: "%02X", cmd)) seq=\(seq)",
                   detail: "帧 \(frame.count)B / \(chunks.count) 包(MTU 负载 \(mtu)B):"
                       + frame.hexString(separator: " "))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func describe(_ packet: Packet) -> String {
        let name = switch packet.cmd {
        case 0x81: "PING 响应"
        case 0x82: "电量响应"
        case 0x83: "版本响应"
        default: "响应"
        }
        return "\(name) cmd=0x\(String(format: "%02X", packet.cmd)) seq=\(packet.seq)"
    }

    private func payloadText(_ payload: Data) -> String {
        guard !payload.isEmpty else { return "(空负载)" }
        var text = payload.hexString(separator: " ")
        if let string = String(data: payload, encoding: .utf8) {
            text += "  |  \"\(string)\""
        }
        return text
    }

    private func append(_ direction: Line.Direction, _ text: String, detail: String? = nil) {
        transcript.append(Line(direction: direction, text: text, detail: detail))
    }
}

struct ProtocolConsoleView: View {

    @State private var model: ProtocolConsoleViewModel

    init(central: any BLECentral, deviceID: UUID) {
        _model = State(initialValue: ProtocolConsoleViewModel(central: central, deviceID: deviceID))
    }

    var body: some View {
        List {
            Section("发送命令") {
                HStack {
                    Button("PING") {
                        Task { await model.send(cmd: 0x01, payload: Data(), label: "PING") }
                    }
                    Button("查电量") {
                        Task { await model.send(cmd: 0x02, payload: Data(), label: "查电量") }
                    }
                    Button("查版本") {
                        Task { await model.send(cmd: 0x03, payload: Data(), label: "查版本") }
                    }
                    Button("大包回显") {
                        // 故意超过一个 MTU,演示分包与组包
                        let payload = Data((0..<60).map { UInt8($0) })
                        Task { await model.send(cmd: 0x10, payload: payload, label: "大包回显") }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section("帧日志") {
                if model.transcript.isEmpty {
                    Text("发送一条命令试试。上行响应会按分片到达并自动组包。")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
                ForEach(model.transcript.reversed()) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(line.text, systemImage: icon(for: line.direction))
                            .font(.footnote.weight(line.direction == .event ? .regular : .medium))
                            .foregroundStyle(color(for: line.direction))
                        if let detail = line.detail {
                            Text(detail)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("私有协议控制台")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run() }
    }

    private func icon(for direction: ProtocolConsoleViewModel.Line.Direction) -> String {
        switch direction {
        case .tx: "arrow.up.circle.fill"
        case .rx: "arrow.down.circle.fill"
        case .event: "info.circle"
        }
    }

    private func color(for direction: ProtocolConsoleViewModel.Line.Direction) -> Color {
        switch direction {
        case .tx: .blue
        case .rx: .green
        case .event: .secondary
        }
    }
}
