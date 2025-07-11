//
//  ReadytoReachLiveActivityLiveActivity.swift
//  ReadytoReachLiveActivity
//
//  Created by Less is more on 15/07/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ReadytoReachLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ReadytoReachLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadytoReachLiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ReadytoReachLiveActivityAttributes {
    fileprivate static var preview: ReadytoReachLiveActivityAttributes {
        ReadytoReachLiveActivityAttributes(name: "World")
    }
}

extension ReadytoReachLiveActivityAttributes.ContentState {
    fileprivate static var smiley: ReadytoReachLiveActivityAttributes.ContentState {
        ReadytoReachLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ReadytoReachLiveActivityAttributes.ContentState {
         ReadytoReachLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ReadytoReachLiveActivityAttributes.preview) {
   ReadytoReachLiveActivityLiveActivity()
} contentStates: {
    ReadytoReachLiveActivityAttributes.ContentState.smiley
    ReadytoReachLiveActivityAttributes.ContentState.starEyes
}
