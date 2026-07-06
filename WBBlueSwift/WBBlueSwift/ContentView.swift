//
//  ContentView.swift
//  WBBlueSwift
//
//  根视图:三个页签。切换数据源(Mock/真实)时以 generation 重建整棵树,
//  保证旧 central 的流被干净取消。
//

import SwiftUI

struct ContentView: View {

    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            Tab("扫描", systemImage: "dot.radiowaves.left.and.right") {
                NavigationStack {
                    ScanView(central: app.central)
                }
            }
            Tab("外设模式", systemImage: "antenna.radiowaves.left.and.right") {
                NavigationStack {
                    PeripheralModeView()
                }
            }
            Tab("日志", systemImage: "doc.text.magnifyingglass") {
                NavigationStack {
                    LogsView()
                }
            }
        }
        .id(app.generation)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
