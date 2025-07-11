//
//  ReadytoReachLiveActivity.swift
//  ReadytoReachLiveActivity
//
//  Created by Less is more on 15/07/2025.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct ReadytoReachLiveActivity: Widget {
    // App Group标识
    let appGroupID = "group.com.zisa.ReadytoReach"
    // 默认logo顺序
    let defaultLogoOrder = [
        "xiaohongshu", "bilibili", "zhihu", "xiaoyuzhou", "youtube", "chrome", "safari", "douyin", "github", "douban"
    ]
    // 获取当前logo顺序
    var logoOrder: [String] {
        if let groupDefaults = UserDefaults(suiteName: appGroupID),
           let arr = groupDefaults.array(forKey: "AppLogoOrderKey") as? [String], !arr.isEmpty {
            return arr
        }
        return defaultLogoOrder
    }
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadytoReachAttributes.self) { context in
            // 锁屏和动态岛外观
            VStack {
                // 移除标题和进度条，只显示消息和 logo 列表
                Text(context.state.message)
                HStack(spacing: 8) {
                    ForEach(logoOrder, id: \.self) { logo in
                        Image(logo)
                            .resizable()
                            .frame(width: 28, height: 28)
                    }
                }
            }
            .padding()
        } dynamicIsland: { context in
            // 动态岛外观
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("  ReadytoReach")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("》》》  ")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        ForEach(logoOrder, id: \.self) { logo in
                            Image(logo).resizable().frame(width: 28, height: 28)
                        }
                    }
                }
            } compactLeading: {
                // 使用放大镜搜索符号
                Image(systemName: "magnifyingglass")
            } compactTrailing: {
                Text("Search")
            } minimal: {
                Image(systemName: "magnifyingglass")
            }
        }
    }
}
