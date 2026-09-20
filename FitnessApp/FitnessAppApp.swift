//
//  FitnessAppApp.swift
//  App 入口。兼容 iOS 16.3.1。
//
//  持久化用 JSONFitnessRepository（FileManager + JSON，落 Application Support），
//  不用 SwiftData —— SwiftData 要求 iOS 17+。
//
//  纯本地：不请求登录、不展示社区内容、不依赖网络。
//

import SwiftUI

@main
struct FitnessAppApp: App {

    /// 本地 JSON 仓储。数据落在 Application Support/FitnessData/ 下的四个 JSON 文件。
    private let repository: JSONFitnessRepository

    init() {
        repository = JSONFitnessRepository()
    }

    var body: some Scene {
        WindowGroup {
            RootView(repository: repository)
                .preferredColorScheme(.dark)
        }
    }
}
