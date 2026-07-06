//
//  LogsView.swift
//  WBBlueSwift
//
//  App 内日志页:读 BLELogger 环形缓冲。现场排障(脱机、无 Xcode)时,
//  这个页面就是第一现场;正式项目通常再加导出/分享。
//

import SwiftUI

struct LogsView: View {

    private let logger = BLELogger.shared
    @State private var levelFilter: BLELogger.Level?

    private var filtered: [BLELogger.Entry] {
        guard let levelFilter else { return logger.entries }
        return logger.entries.filter { $0.level == levelFilter }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Text("暂无日志")
                    .foregroundStyle(.secondary)
            }
            ForEach(filtered.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.level.rawValue)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color(for: entry.level))
                        Text("[\(entry.category)]")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.date, format: .dateTime.hour().minute().second(.twoDigits))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.message)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("日志(\(filtered.count))")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("全部") { levelFilter = nil }
                    ForEach(BLELogger.Level.allCases, id: \.self) { level in
                        Button(level.rawValue) { levelFilter = level }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("清空") { logger.clear() }
            }
        }
    }

    private func color(for level: BLELogger.Level) -> Color {
        switch level {
        case .debug: .gray
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
