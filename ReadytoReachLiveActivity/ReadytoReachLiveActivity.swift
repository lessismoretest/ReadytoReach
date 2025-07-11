//
//  ReadytoReachLiveActivity.swift
//  ReadytoReachLiveActivity
//
//  Created by Less is more on 15/07/2025.
//

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import UIKit

struct ReadytoReachLiveActivity: Widget {
    // App Group标识
    let appGroupID = "group.com.zisa.ReadytoReach"
    // 默认logo顺序
    let defaultLogoOrder = [
        "xiaohongshu", "bilibili", "zhihu", "xiaoyuzhou", "youtube", "chrome", "safari", "douyin", "github", "douban"
    ]
    
    /// 获取当前可见 Logo 顺序（从 App Group 读取，未找到则使用默认值）
    /// - Returns: 当前用于展示的 Logo 名称数组
    func getLogoOrder() -> [String] {
        if let groupDefaults = UserDefaults(suiteName: appGroupID) {
            // 强制同步，确保读取最新数据
            groupDefaults.synchronize()
            
            if let arr = groupDefaults.array(forKey: "AppLogoOrderKey") as? [String], !arr.isEmpty {
                print("📱 Live Activity读取到 \(arr.count) 个图标: \(arr)")
                return arr
            } else {
                print("⚠️ Live Activity未找到AppLogoOrderKey，使用默认顺序")
            }
        } else {
            print("❌ Live Activity无法访问App Group")
        }
        print("📱 Live Activity使用默认顺序: \(defaultLogoOrder.count) 个图标")
        return defaultLogoOrder
    }
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadytoReachAttributes.self) { context in
            // 锁屏和动态岛外观
            // 使用函数获取最新顺序，确保每次渲染时都读取最新值
            let currentLogoOrder = getLogoOrder()
            VStack {
                // 移除标题和进度条，只显示消息和 logo 列表
                Text(context.state.message)
                // 锁屏/通知横幅采用两行八列网格，总计最多显示16个图标，间距增大
                // 锁屏/通知横幅改为两行七列网格，总计最多显示14个图标，并放大图标且居中对齐
                let lockGridIcons = Array(currentLogoOrder.prefix(14))
                // 使用灵活列宽使网格占满可用宽度，从而居中每列内容，避免左右边距不一致
                let lockColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 7)
                LazyVGrid(columns: lockColumns, alignment: .center, spacing: 12) {
                    ForEach(lockGridIcons, id: \.self) { logo in
                        Link(destination: URL(string: "readytoreach://open?logo=\(logo)") ?? URL(string: "readytoreach://")!) {
                            if UIImage(named: logo) != nil {
                                Image(logo)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(systemName: "app")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }
            .padding()
            // 显式去除活动背景着色，避免出现突兀的彩色矩形条
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            // 动态岛外观
            // 使用函数获取最新顺序，确保每次渲染时都读取最新值
            let currentLogoOrder = getLogoOrder()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Search")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "magnifyingglass")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 动态岛展开区域采用两行七列网格，总计最多显示14个图标（居中对齐）
                    let gridIcons = Array(currentLogoOrder.prefix(14))
                    let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 12), count: 7)
                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(gridIcons, id: \.self) { logo in
                            Link(destination: URL(string: "readytoreach://open?logo=\(logo)") ?? URL(string: "readytoreach://")!) {
                                if UIImage(named: logo) != nil {
                                    Image(logo)
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                } else {
                                    Image(systemName: "app")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            } compactLeading: {
                // 使用放大镜搜索符号
                Image(systemName: "magnifyingglass")
            } compactTrailing: {
                // 使用简洁图标，避免紧凑区域出现高亮背景
                Image(systemName: "magnifyingglass")
            } minimal: {
                Image(systemName: "magnifyingglass")
            }
            // 关闭系统关键线着色，避免出现显眼的红色“禁止”或其他系统强调图标
            .keylineTint(.clear)
        }
    }
}
