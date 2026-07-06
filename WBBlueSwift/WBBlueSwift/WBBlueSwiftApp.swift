//
//  WBBlueSwiftApp.swift
//  WBBlueSwift
//
//  入口:注入应用级依赖容器 AppModel(内含 BLECentral 双实现)。
//

import SwiftUI

@main
struct WBBlueSwiftApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
    }
}
