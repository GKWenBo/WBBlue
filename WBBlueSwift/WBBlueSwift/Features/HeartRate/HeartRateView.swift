//
//  HeartRateView.swift
//  WBBlueSwift
//
//  实时心率:订阅 0x2A37 → 解析 → Swift Charts 滑动窗口曲线。
//  视图 .task 驱动订阅任务:离开页面任务取消 → 流终止 → 自动关闭 CCCD。
//

import Charts
import CoreBluetooth
import Foundation
import SwiftUI

@Observable
final class HeartRateViewModel {

    struct Sample: Identifiable {
        let id = UUID()
        let date: Date
        let bpm: Int
    }

    private let central: any BLECentral
    private let deviceID: UUID
    /// 滑动窗口长度
    private let windowSize = 90

    var samples: [Sample] = []
    var current: HeartRateMeasurement?
    var errorMessage: String?

    init(central: any BLECentral, deviceID: UUID) {
        self.central = central
        self.deviceID = deviceID
    }

    func run() async {
        do {
            let stream = try await central.notifications(
                id: deviceID, characteristic: BLEConstants.heartRateMeasurement
            )
            errorMessage = nil
            for try await data in stream {
                guard let measurement = HeartRateParser.parse(data) else {
                    BLELogger.shared.log(.warning, category: "心率",
                                         "无法解析:\(data.hexString(separator: " "))")
                    continue
                }
                current = measurement
                samples.append(Sample(date: .now, bpm: measurement.bpm))
                if samples.count > windowSize {
                    samples.removeFirst(samples.count - windowSize)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct HeartRateView: View {

    @State private var model: HeartRateViewModel

    init(central: any BLECentral, deviceID: UUID) {
        _model = State(initialValue: HeartRateViewModel(central: central, deviceID: deviceID))
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: model.current != nil)
                    Text(model.current.map { "\($0.bpm)" } ?? "--")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("bpm")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let current = model.current {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(contactText(current.sensorContact))
                            if let energy = current.energyExpended {
                                Text("能耗 \(energy) kJ")
                            }
                            if let rr = current.rrIntervals.last {
                                Text(String(format: "RR %.0f ms", rr * 1000))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section("最近 90 秒") {
                if model.samples.isEmpty {
                    Text(model.errorMessage ?? "等待第一帧通知…")
                        .foregroundStyle(model.errorMessage == nil ? .secondary : Color.red)
                } else {
                    Chart(model.samples) { sample in
                        LineMark(x: .value("时间", sample.date), y: .value("bpm", sample.bpm))
                            .interpolationMethod(.catmullRom)
                        AreaMark(x: .value("时间", sample.date), y: .value("bpm", sample.bpm))
                            .foregroundStyle(.linearGradient(
                                colors: [.red.opacity(0.25), .clear],
                                startPoint: .top, endPoint: .bottom
                            ))
                    }
                    .foregroundStyle(.red)
                    .chartYScale(domain: 40...140)
                    .frame(height: 220)
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("实时心率")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run() }
    }

    private func contactText(_ contact: HeartRateMeasurement.SensorContact) -> String {
        switch contact {
        case .notSupported: "无接触检测"
        case .noContact: "未接触皮肤"
        case .contactDetected: "接触良好"
        }
    }
}
