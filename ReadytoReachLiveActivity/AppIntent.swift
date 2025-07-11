//
//  AppIntent.swift
//  ReadytoReachLiveActivity
//
//  Created by Less is more on 15/07/2025.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Favorite Emoji", default: "😃")
    var favoriteEmoji: String
}

// 注意：OpenSearchItemIntent 已不再使用，因为我们已经改用 Link 方式通过 URL scheme 处理点击
// 如果需要使用 App Intent，可以在主 App 中实现，而不是在 Extension 中
