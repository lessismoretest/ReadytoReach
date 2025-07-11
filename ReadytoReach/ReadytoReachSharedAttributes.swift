import ActivityKit

// 实时活动属性结构体（主App和Widget Extension共享）
public struct ReadytoReachAttributes: ActivityAttributes {
    // 实时变化的数据
    public struct ContentState: Codable, Hashable {
        public var progress: Double // 进度百分比 0.0~1.0
        public var message: String  // 状态信息
        public init(progress: Double, message: String) {
            self.progress = progress
            self.message = message
        }
    }
    // 固定不变的数据
    public var title: String // 活动标题
    public init(title: String) {
        self.title = title
    }
} 