//
//  ContentView.swift
//  ReadytoReach
//
//  Created by Less is more on 11/07/2025.
//

import SwiftUI
import Speech // 导入语音识别框架
import UIKit // 新增，支持自定义输入框
import AVFoundation // 新增：用于播放系统音效
import ActivityKit // 新增：用于实时活动
import UserNotifications
import WidgetKit
import AudioToolbox // 新增：用于播放系统音效

// 输入框控制器，持有UITextField弱引用
class SearchTextFieldController: ObservableObject {
    weak var textField: UITextField?
    func insertTextAtCursor(_ text: String) {
        guard let tf = textField else { return }
        if let selectedRange = tf.selectedTextRange {
            tf.replace(selectedRange, withText: text)
        } else {
            tf.text = (tf.text ?? "") + text
        }
        tf.sendActions(for: .editingChanged)
    }
}

// 添加 SpeechRecognizer 类（可放在 ContentView 之前）
class SpeechRecognizer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    @Published var isRecording = false

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                completion(authStatus == .authorized)
            }
        }
    }

    func startRecording(onResult: @escaping (String, Bool) -> Void) {
        if audioEngine.isRunning { stopRecording(); return }
        let node = audioEngine.inputNode
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            }
        }
        let recordingFormat = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
    }
}

struct ContentView: View {
    // 搜索内容绑定变量
    @State private var searchText: String = ""
    // 控制输入框焦点的变量
    @State private var isFirstResponder = false // 新增普通 State 控制输入框焦点
    @State private var isKeyboardVisible = false // 新增
    // 移除语音识别相关状态
    // @State private var isRecording = false
    // @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    // @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    // @State private var recognitionTask: SFSpeechRecognitionTask?
    // @State private var audioEngine = AVAudioEngine()
    @State private var isShowingSettings = false
    // 颜色模式设置
    @State private var colorSchemeSetting: ColorSchemeSetting = .system
    // 新增：设置弹窗类型
    enum SettingSheetType { case none, color, logoSize, defaultApp, defaultBrowser, overRecognition, appIcon } // 新增appIcon
    @State private var settingSheetType: SettingSheetType = .none
    // 新增：logo大小设置
    enum LogoSizeType: String, CaseIterable, Identifiable, Codable {
        case small, medium, large, extraLarge 
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .small: return "小"
            case .medium: return "中"
            case .large: return "大"
            case .extraLarge: return "超大" 
            }
        }
        var size: CGFloat {
            switch self {
            case .small: return 28
            case .medium: return 32
            case .large: return 36
            case .extraLarge: return 40 
            }
        }
    }
    @State private var logoSizeType: LogoSizeType = .extraLarge
    @State private var showLogoSizeSheet = false
    private let logoSizeTypeKey = "LogoSizeTypeKey"
    // 颜色模式枚举
    enum ColorSchemeSetting: String, CaseIterable, Identifiable, Codable {
        case system, light, dark
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
    }
    // 控制颜色设置弹窗
    @State private var showColorSheet = false
    // 默认搜索App的UserDefaults key
    private let defaultSearchAppKey = "DefaultSearchAppKey"
    // 当前默认搜索App的名字，初始值为小红书
    @State private var defaultSearchAppName: String = "小红书"
    // 控制默认搜索App选择弹窗
    @State private var showDefaultSearchAppSheet = false
    // 删除selectedAppIndex和selectedWebIndex，合并为selectedIndex
    @State private var selectedIndex: Int = 0
    // 控制是否显示历史记录
    @State private var isShowingHistory = false
    // 搜索模式枚举
    enum SearchMode: String, CaseIterable, Identifiable, Codable {
        case app, web
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .app: return "App搜索"
            case .web: return "Web搜索"
            }
        }
    }
    // 历史记录结构体
    struct SearchHistoryItem: Identifiable, Codable {
        let id = UUID()
        let date: Date
        let keyword: String
        let appName: String // 统一用unifiedList的name
        let appLogo: String // 统一用unifiedList的logo
        let mode: SearchMode // 新增：记录当时的搜索模式
    }
    // 历史记录数组
    @State private var searchHistory: [SearchHistoryItem] = []
    // 历史记录UserDefaults key
    private let searchHistoryKey = "SearchHistoryKey"
    // 剪切板历史结构体
    struct ClipboardHistoryItem: Identifiable, Codable {
        let id = UUID()
        let content: String
        let date: Date
    }
    // 剪切板历史数组
    @State private var clipboardHistory: [ClipboardHistoryItem] = []
    // 剪切板历史UserDefaults key
    private let clipboardHistoryKey = "ClipboardHistoryKey"
    // 收藏夹结构体
    struct FavoriteItem: Identifiable, Codable {
        let id = UUID()
        let content: String
        let date: Date
    }
    // 收藏夹数组
    @State private var favorites: [FavoriteItem] = []
    // 收藏夹UserDefaults key
    private let favoritesKey = "FavoritesKey"
    // 剪切板纵向列表切换和清空弹窗
    @State private var isShowingClipboardList = false
    @State private var isShowingFavorites = false // 新增：控制是否显示收藏夹列表
    @State private var showClearClipboardAlert = false
    @Environment(\.scenePhase) private var scenePhase // 监听App生命周期
    
    // 清空全部历史
    @State private var showClearHistoryAlert = false
    // 当前搜索模式
    @State private var searchMode: SearchMode = .app
    // 默认Web浏览器设置
    enum WebBrowserType: String, CaseIterable, Identifiable, Codable {
        case chrome, safari
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .chrome: return "Chrome"
            case .safari: return "Safari"
            }
        }
        var schemePrefix: String {
            switch self {
            case .chrome: return "googlechrome://"
            case .safari: return "https://"
            }
        }
    }
    private let defaultWebBrowserKey = "DefaultWebBrowserKey"
    @State private var defaultWebBrowser: WebBrowserType = .chrome
    @State private var showWebBrowserSheet = false
    // 统一的搜索项结构体，融合App和Web
    struct UnifiedSearchItem: Identifiable, Codable, Equatable, Hashable {
        let id = UUID()
        let name: String
        let logo: String
        let appUrlScheme: String? // App模式下的urlScheme，可为nil
        let webUrl: String?       // Web模式下的url，可为nil
        var isHidden: Bool = false // 新增：是否隐藏
        // 新增：App和Web模式的自定义关键词
        var appKeyword: String? = nil
        var webKeyword: String? = nil
    }
    // 默认的统一搜索项列表（合并app和web，去重）
    private let defaultUnifiedList: [UnifiedSearchItem] = [
        UnifiedSearchItem(name: "小红书", logo: "xiaohongshu", appUrlScheme: "xhsdiscover://search/result?keyword={query}", webUrl: "www.xiaohongshu.com/search_result?keyword={query}", appKeyword: "xhs", webKeyword: "xhsw"),
        UnifiedSearchItem(name: "哔哩哔哩", logo: "bilibili", appUrlScheme: "bilibili://search?keyword={query}", webUrl: "www.bilibili.com/search?keyword={query}", appKeyword: "bl", webKeyword: "blw"),
        UnifiedSearchItem(name: "知乎", logo: "zhihu", appUrlScheme: "zhihu://search?q={query}", webUrl: "www.zhihu.com/search?type=content&q={query}", appKeyword: "zh", webKeyword: "zhw"),
        UnifiedSearchItem(name: "小宇宙", logo: "xiaoyuzhou", appUrlScheme: "cosmos://search?q={query}", webUrl: nil, appKeyword: "xyz", webKeyword: nil),
        UnifiedSearchItem(name: "YouTube", logo: "youtube", appUrlScheme: "youtube:///results?q={query}", webUrl: "www.youtube.com/results?search_query={query}", appKeyword: "yt", webKeyword: "ytw"),
        UnifiedSearchItem(name: "Chrome", logo: "chrome", appUrlScheme: "googlechrome://www.google.com/search?q={query}", webUrl: "www.google.com/search?q={query}", appKeyword: "ch", webKeyword: "chw"),
        UnifiedSearchItem(name: "Safari", logo: "safari", appUrlScheme: "x-web-search://?{query}", webUrl: nil, appKeyword: "sa", webKeyword: nil),
        UnifiedSearchItem(name: "抖音", logo: "douyin", appUrlScheme: "snssdk1128://search?keyword={query}", webUrl: nil, appKeyword: "dy", webKeyword: nil),
        UnifiedSearchItem(name: "GitHub", logo: "github", appUrlScheme: "github://search?q={query}", webUrl: "github.com/search?q={query}", appKeyword: "gh", webKeyword: "ghw"),
        UnifiedSearchItem(name: "豆瓣", logo: "douban", appUrlScheme: "douban://search?q={query}", webUrl: "www.douban.com/search?q={query}", appKeyword: "db", webKeyword: "dbw"),
        UnifiedSearchItem(name: "百度", logo: "baidu", appUrlScheme: nil, webUrl: "www.baidu.com/s?wd={query}", appKeyword: nil, webKeyword: "bd"),
        UnifiedSearchItem(name: "Google", logo: "google", appUrlScheme: nil, webUrl: "www.google.com/search?q={query}", appKeyword: nil, webKeyword: "gg"),
        // 新增平台
        UnifiedSearchItem(name: "Pinterest", logo: "pinterest", appUrlScheme: "pinterest://search/pins/?q={query}", webUrl: "www.pinterest.com/search/pins/?q={query}", appKeyword: "pt", webKeyword: "ptw"),
        UnifiedSearchItem(name: "X（Twitter）", logo: "twitter", appUrlScheme: "twitter://search?query={query}", webUrl: "x.com/search?q={query}", appKeyword: "tw", webKeyword: "tww"),
        UnifiedSearchItem(name: "Wikipedia", logo: "wikipedia", appUrlScheme: nil, webUrl: "en.wikipedia.org/wiki/Special:Search?search={query}", appKeyword: nil, webKeyword: "wiki"),
        UnifiedSearchItem(name: "Amazon", logo: "amazon", appUrlScheme: "amazon://search?keyword={query}", webUrl: "www.amazon.com/s?k={query}", appKeyword: "amz", webKeyword: "amzw"),
        UnifiedSearchItem(name: "IMDb", logo: "imdb", appUrlScheme: "imdb:///find?q={query}", webUrl: "www.imdb.com/find?q={query}", appKeyword: "imdb", webKeyword: "imdbw"),
        UnifiedSearchItem(name: "eBay", logo: "ebay", appUrlScheme: "ebay://search?query={query}", webUrl: "www.ebay.com/sch/i.html?_nkw={query}", appKeyword: "eb", webKeyword: "ebw"),
        UnifiedSearchItem(name: "Bing", logo: "bing", appUrlScheme: nil, webUrl: "www.bing.com/search?q={query}", appKeyword: nil, webKeyword: "bing"),
        UnifiedSearchItem(name: "Yahoo", logo: "yahoo", appUrlScheme: nil, webUrl: "search.yahoo.com/search?p={query}", appKeyword: nil, webKeyword: "yahoo"),
        UnifiedSearchItem(name: "Facebook", logo: "facebook", appUrlScheme: "fb://search/?q={query}", webUrl: "www.facebook.com/search/top/?q={query}", appKeyword: "fb", webKeyword: "fbw"),
        UnifiedSearchItem(name: "Instagram", logo: "instagram", appUrlScheme: "instagram://tag?name={query}", webUrl: "www.instagram.com/explore/tags/{query}/", appKeyword: "ins", webKeyword: "insw"),
        UnifiedSearchItem(name: "DuckDuckGo", logo: "duckduckgo", appUrlScheme: nil, webUrl: "duckduckgo.com/?q={query}", appKeyword: nil, webKeyword: "duck"),
        UnifiedSearchItem(name: "淘宝", logo: "taobao", appUrlScheme: "taobao://search?q={query}", webUrl: "s.taobao.com/search?q={query}", appKeyword: "tb", webKeyword: "tbw"),
        UnifiedSearchItem(name: "天猫", logo: "tmall", appUrlScheme: "tmall://search?q={query}", webUrl: "list.tmall.com/search_product.htm?q={query}", appKeyword: "tm", webKeyword: "tmw"),
        UnifiedSearchItem(name: "京东", logo: "jd", appUrlScheme: "openapp.jdmobile://virtual?params={\"category\":\"jump\",\"des\":\"search\",\"keyword\":\"{query}\"}", webUrl: "search.jd.com/Search?keyword={query}", appKeyword: "jd", webKeyword: "jdw"),
        UnifiedSearchItem(name: "什么值得买", logo: "smzdm", appUrlScheme: "smzdm://search?keyword={query}", webUrl: "search.smzdm.com/?s={query}", appKeyword: "smzdm", webKeyword: "smzdmw"),
        UnifiedSearchItem(name: "Product Hunt", logo: "producthunt", appUrlScheme: nil, webUrl: "www.producthunt.com/search?q={query}", appKeyword: nil, webKeyword: "ph"),
        UnifiedSearchItem(name: "Reddit", logo: "reddit", appUrlScheme: "reddit://search/?q={query}", webUrl: "www.reddit.com/search/?q={query}", appKeyword: "rd", webKeyword: "rdw"),
        UnifiedSearchItem(name: "微博", logo: "weibo", appUrlScheme: "sinaweibo://searchall?keyword={query}", webUrl: "s.weibo.com/weibo/{query}", appKeyword: "wb", webKeyword: "wbw")
    ]
    // 新增unifiedList排序持久化key
    private let unifiedListOrderKey = "UnifiedListOrderKey"
    // 在ContentView的@State中新增每条目的模式状态
    @State private var itemModeDict: [String: SearchMode] = [:]
    // 新增：输入框控制器，持有UITextField弱引用
    @StateObject private var searchTextFieldController = SearchTextFieldController()
    @State private var showClearFavoritesAlert = false
    // 新增：selectedIndex 持久化 key
    private let lastSelectedIndexKey = "LastSelectedIndexKey"
    // 替换 selectedIndex 为 selectedLogoId
    @State private var selectedLogoId: String? = nil
    private let lastSelectedLogoIdKey = "LastSelectedLogoIdKey"
    // 剪切板横向滚动区点击高亮
    @State private var recentClipboardTappedId: UUID? = nil
    @State private var clipboardHasNew: Bool = false
    // 新增：搜索项管理设置数组
    @State private var searchItemSettings: [UnifiedSearchItem] = []
    private let searchItemSettingsKey = "SearchItemSettingsKey"
    @State private var incognitoMode: Bool = false // 新增：无痕搜索开关
    // 新增：历史多选删除相关状态
    @State private var isEditingHistory = false
    @State private var selectedHistoryIds: Set<UUID> = []
    @State private var showLogoBar: Bool = true
    @State private var showHistoryBar: Bool = true
    @State private var showFavoritesBar: Bool = true
    @State private var showClipboardBar: Bool = true
    private let quickBarSettingsKey = "QuickBarSettingsKey"
    // 新增：快捷操作区结构体
    struct QuickBarItem: Identifiable, Codable, Equatable {
        let id: String
        let name: String
        let icon: String // systemName
        var isOn: Bool
    }
    @State private var quickBarItems: [QuickBarItem] = []
    private let quickBarItemsKey = "QuickBarItemsKey"
    let defaultQuickBarItems: [QuickBarItem] = [
        .init(id: "clipboard", name: "剪切板横向滚动区", icon: "doc.on.clipboard", isOn: true),
        .init(id: "favorites", name: "快捷短语横向滚动区", icon: "pencil.line", isOn: true),
        .init(id: "history", name: "历史记录横向滚动区", icon: "clock.arrow.circlepath", isOn: true),
        .init(id: "logo", name: "Logo横向滚动区", icon: "iphone.app.switcher", isOn: true)
    ]
    func loadQuickBarItems() {
        if let data = UserDefaults.standard.data(forKey: quickBarItemsKey),
           let arr = try? JSONDecoder().decode([QuickBarItem].self, from: data) {
            quickBarItems = arr
        } else {
            quickBarItems = defaultQuickBarItems
        }
    }
    func saveQuickBarItems() {
        if let data = try? JSONEncoder().encode(quickBarItems) {
            UserDefaults.standard.set(data, forKey: quickBarItemsKey)
        }
    }
    @State private var autoFocusOnLaunch: Bool = true
    private let autoFocusOnLaunchKey = "AutoFocusOnLaunchKey"
    func saveAutoFocusOnLaunch() {
        UserDefaults.standard.set(autoFocusOnLaunch, forKey: autoFocusOnLaunchKey)
    }
    func loadAutoFocusOnLaunch() {
        if UserDefaults.standard.object(forKey: autoFocusOnLaunchKey) != nil {
            autoFocusOnLaunch = UserDefaults.standard.bool(forKey: autoFocusOnLaunchKey)
        } else {
            autoFocusOnLaunch = true
        }
    }
    // 新增：启动时自动语音开关
    @State private var autoStartVoiceOnLaunch: Bool = true
    private let autoStartVoiceOnLaunchKey = "AutoStartVoiceOnLaunchKey"
    func saveAutoStartVoiceOnLaunch() {
        UserDefaults.standard.set(autoStartVoiceOnLaunch, forKey: autoStartVoiceOnLaunchKey)
    }
    func loadAutoStartVoiceOnLaunch() {
        if UserDefaults.standard.object(forKey: autoStartVoiceOnLaunchKey) != nil {
            autoStartVoiceOnLaunch = UserDefaults.standard.bool(forKey: autoStartVoiceOnLaunchKey)
        } else {
            autoStartVoiceOnLaunch = true
        }
    }
    @State private var showMainList: Bool = false // 默认关闭纵向列表
    private let showMainListKey = "ShowMainListKey"
    func saveShowMainList() {
        UserDefaults.standard.set(showMainList, forKey: showMainListKey)
    }
    func loadShowMainList() {
        if UserDefaults.standard.object(forKey: showMainListKey) != nil {
            showMainList = UserDefaults.standard.bool(forKey: showMainListKey)
        } else {
            showMainList = false // 默认关闭
        }
    }
    @StateObject private var speechRecognizer = SpeechRecognizer() // 新增：语音识别管理器
    // 新增：over识别模式设置
    enum OverRecognitionMode: String, CaseIterable, Identifiable, Codable {
        case off, single, double
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .off: return "关闭"
            case .single: return "over"
            case .double: return "over over"
            }
        }
    }
    @State private var overRecognitionMode: OverRecognitionMode = .double
    private let overRecognitionModeKey = "OverRecognitionModeKey"
    func saveOverRecognitionMode() {
        UserDefaults.standard.set(overRecognitionMode.rawValue, forKey: overRecognitionModeKey)
    }
    func loadOverRecognitionMode() {
        if let raw = UserDefaults.standard.string(forKey: overRecognitionModeKey),
           let mode = OverRecognitionMode(rawValue: raw) {
            overRecognitionMode = mode
        } else {
            overRecognitionMode = .double
        }
    }
    @State private var currentAppIconDisplayName: String = "默认" // 新增：当前图标显示名
    @State private var speechAutoJumpTimer: Timer? = nil // 新增：语音自动跳转定时器
    var body: some View {
        let sortedClipboard = clipboardHistory.sorted(by: { $0.date > $1.date })
        let latestId = sortedClipboard.first?.id
        VStack {
            // 判断是否显示设置列表
            if isShowingSettings {
                List {
                    // 第一项：返回搜索列表
                    Button(action: {
                        isShowingSettings = false
                        isShowingClipboardList = false
                        // 移除失焦和聚焦逻辑，输入框状态不变
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "arrow.left")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.blue)
                            }
                            Text("返回搜索列表")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                        }
                        .padding(.vertical, 4)
                    }
                    // 颜色设置
                    Button(action: {
                        settingSheetType = .color
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "paintpalette")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.orange)
                            }
                            Text("颜色")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(colorSchemeSetting.displayName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // Logo大小
                    Button(action: {
                        settingSheetType = .logoSize
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "rectangle.and.hand.point.up.left.filled")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.indigo)
                            }
                            Text("Logo大小")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(logoSizeType.displayName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // 启动时默认聚焦搜索开关（已移至Logo大小下方）
                    Toggle(isOn: $autoFocusOnLaunch) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "cursorarrow.rays")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.blue)
                            }
                            Text("启动时聚焦搜索") // 文案修改
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                        }
                    }
                    .onChange(of: autoFocusOnLaunch) { _ in
                        saveAutoFocusOnLaunch()
                    }
                    .padding(.vertical, 4)
                    // 新增：启动时自动语音开关
                    Toggle(isOn: $autoStartVoiceOnLaunch) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "mic")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.red)
                            }
                            Text("启动时打开语音")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                        }
                    }
                    .onChange(of: autoStartVoiceOnLaunch) { _ in
                        saveAutoStartVoiceOnLaunch()
                    }
                    .padding(.vertical, 4)
                    // 无痕搜索（单独一项）
                    Toggle(isOn: $incognitoMode) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "eye.slash")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.gray)
                            }
                            Text("无痕搜索")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                        }
                    }
                    .padding(.vertical, 4)
                    // 默认搜索App（单独一项）
                    Button(action: {
                        settingSheetType = .defaultApp
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "magnifyingglass")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.purple)
                            }
                            Text("默认搜索App")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(defaultSearchAppName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // 默认搜索浏览器（单独一项）
                    Button(action: {
                        settingSheetType = .defaultBrowser
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "globe")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.green)
                            }
                            Text("默认搜索浏览器")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(defaultWebBrowser.displayName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // 新增：over识别模式设置项
                    Button(action: {
                        settingSheetType = .overRecognition
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "waveform")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.purple)
                            }
                            Text("语音over识别模式")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(overRecognitionMode.displayName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // 新增：应用图标选择
                    Button(action: {
                        settingSheetType = .appIcon
                    }) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "app.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.blue)
                            }
                            Text("应用图标")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                            Spacer()
                            Text(currentAppIconDisplayName)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                    // 纵向列表显示开关
                    Toggle(isOn: $showMainList) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.systemGray5))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "list.bullet")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .foregroundColor(.teal)
                            }
                            Text("显示纵向列表")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 12)
                        }
                    }
                    .onChange(of: showMainList) { _ in
                        saveShowMainList()
                    }
                    .padding(.vertical, 4)
                    // 快捷操作区管理
                    Section(header: Text("快捷操作区管理")) {
                        ForEach($quickBarItems) { $item in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.gray)
                                    .frame(width: 20)
                                Image(systemName: item.icon)
                                    .foregroundColor(.gray)
                                    .frame(width: 20)
                                Text(item.name)
                                    .font(.body)
                                Spacer()
                                Toggle("", isOn: $item.isOn)
                                    .labelsHidden()
                                    .onChange(of: item.isOn) { _ in
                                        saveQuickBarItems()
                                    }
                            }
                        }
                        .onMove { indices, newOffset in
                            quickBarItems.move(fromOffsets: indices, toOffset: newOffset)
                            saveQuickBarItems()
                        }
                    }
                    // 搜索项管理分组
                    Section(header: Text("搜索项管理")) {
                        ForEach(searchItemSettings) { item in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.gray)
                                    .frame(width: 20)
                                if UIImage(named: item.logo) != nil {
                                    Image(item.logo)
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                } else {
                                    Image(systemName: "app")
                                        .resizable()
                                        .frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.body)
                                        .padding(.leading, 8)
                                    HStack(spacing: 12) {
                                        if let appKey = item.appKeyword, !appKey.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "a.square.fill")
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                    .foregroundColor(.blue)
                                                Text(appKey)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        if let webKey = item.webKeyword, !webKey.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "globe")
                                                    .resizable()
                                                    .frame(width: 14, height: 14)
                                                    .foregroundColor(.green)
                                                Text(webKey)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                    .padding(.leading, 8)
                                }
                                Spacer()
                                Toggle("显示", isOn: Binding(
                                    get: { !item.isHidden },
                                    set: { newValue in
                                        if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                            searchItemSettings[idx].isHidden = !newValue
                                            saveSearchItemSettings()
                                        }
                                    })
                                )
                                .labelsHidden()
                            }
                        }
                        .onMove { indices, newOffset in
                            searchItemSettings.move(fromOffsets: indices, toOffset: newOffset)
                            saveSearchItemSettings()
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .toolbar { EditButton() }
            } else {
                if isShowingHistory {
                    // 展示历史记录
                    VStack(spacing: 0) {
                        HStack {
                            Text("历史记录")
                                .font(.headline)
                                .padding(.leading)
                            Spacer()
                            if isEditingHistory {
                                Button(action: {
                                    // 退出多选模式
                                    isEditingHistory = false
                                    selectedHistoryIds.removeAll()
                                }) {
                                    Text("完成")
                                }
                                .padding(.trailing, 8)
                                Button(action: {
                                    // 删除选中项
                                    let sorted = searchHistory.sorted(by: { $0.date > $1.date })
                                    let offsets = IndexSet(sorted.enumerated().compactMap { idx, item in
                                        selectedHistoryIds.contains(item.id) ? idx : nil
                                    })
                                    deleteHistory(at: offsets)
                                    selectedHistoryIds.removeAll()
                                    if searchHistory.isEmpty {
                                        isEditingHistory = false
                                    }
                                }) {
                                    Text("删除(") + Text("\(selectedHistoryIds.count)").foregroundColor(.red) + Text(")")
                                }
                                .disabled(selectedHistoryIds.isEmpty)
                                .padding(.trailing)
                            } else {
                                Button(action: {
                                    isEditingHistory = true
                                }) {
                                    Text("多选")
                                }
                                .padding(.trailing, 8)
                                Button(action: {
                                    showClearHistoryAlert = true
                                }) {
                                    Text("清空")
                                        .foregroundColor(.red)
                                }
                                .padding(.trailing)
                            }
                        }
                        .frame(height: 36)
                        .background(Color(.systemBackground))
                        Divider()
                    List {
                        ForEach(searchHistory.sorted(by: { $0.date > $1.date })) { item in
                            HStack(alignment: .center) {
                                if isEditingHistory {
                                    Button(action: {
                                        if selectedHistoryIds.contains(item.id) {
                                            selectedHistoryIds.remove(item.id)
                                        } else {
                                            selectedHistoryIds.insert(item.id)
                                        }
                                    }) {
                                        Image(systemName: selectedHistoryIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedHistoryIds.contains(item.id) ? .blue : .gray)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                                Group {
                                    if UIImage(named: item.appLogo) != nil {
                                        Image(item.appLogo)
                                            .resizable()
                                    } else {
                                        Image(systemName: "app")
                                            .resizable()
                                    }
                                }
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.keyword)
                                        .font(.headline)
                                    HStack(spacing: 4) {
                                        // 模式标识移到appName左侧
                                        Image(systemName: item.mode == .app ? "a.square.fill" : "globe")
                                            .resizable()
                                            .frame(width: 14, height: 14)
                                            .foregroundColor(item.mode == .app ? .blue : .green)
                                        Text(item.appName)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text(historyDateString(item.date))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isEditingHistory {
                                    if selectedHistoryIds.contains(item.id) {
                                        selectedHistoryIds.remove(item.id)
                                    } else {
                                        selectedHistoryIds.insert(item.id)
                                    }
                                } else {
                                    self.searchText = item.keyword
                                    if let idx = searchItemSettings.firstIndex(where: { $0.name == item.appName }) {
                                        let query = item.keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if let scheme = searchItemSettings[idx].appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                            UIApplication.shared.open(url)
                                            addSearchHistory(keyword: item.keyword, appName: item.appName, appLogo: item.appLogo, mode: item.mode)
                                        } else if let webUrl = searchItemSettings[idx].webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    }
                                    self.isShowingHistory = false
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isEditingHistory {
                                    Button {
                                        self.searchText = item.keyword
                                        self.isFirstResponder = true
                                    } label: {
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    .tint(.blue)
                                    Button {
                                        if let idx = favorites.firstIndex(where: { $0.content == item.keyword }) {
                                            favorites.remove(at: idx)
                                            saveFavorites()
                                        } else {
                                            addFavorite(content: item.keyword)
                                        }
                                    } label: {
                                        Image(systemName: "pencil.line")
                                    }
                                    .tint(.orange)
                                    Button(role: .destructive) {
                                        if let index = searchHistory.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = searchHistory.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteHistory(at: offsets)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                            .contextMenu {
                                if !isEditingHistory {
                                    Button {
                                        self.searchText = item.keyword
                                        self.isFirstResponder = true
                                    } label: {
                                        Text("插入")
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    Button {
                                        if let idx = favorites.firstIndex(where: { $0.content == item.keyword }) {
                                            favorites.remove(at: idx)
                                            saveFavorites()
                                        } else {
                                            addFavorite(content: item.keyword)
                                        }
                                    } label: {
                                        Text(favorites.contains(where: { $0.content == item.keyword }) ? "移除快捷" : "快捷")
                                        Image(systemName: "pencil.line")
                                    }
                                    Button(role: .destructive) {
                                        if let index = searchHistory.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = searchHistory.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteHistory(at: offsets)
                                        }
                                    } label: {
                                        Text("删除")
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                        .onDelete(perform: { offsets in
                            if isEditingHistory {
                                // 多选模式下不响应单条删除
                                return
                            }
                            deleteHistory(at: offsets)
                        })
                    }
                    .listStyle(PlainListStyle())
                    }
                    .alert(isPresented: $showClearHistoryAlert) {
                        Alert(title: Text("确认清空历史记录？"), message: nil, primaryButton: .destructive(Text("清空")) {
                            clearAllHistory()
                        }, secondaryButton: .cancel())
                    }
                } else if isShowingClipboardList {
                    // 剪切板历史列表
                    VStack(spacing: 0) {
                        HStack {
                            Text("剪切板")
                                .font(.headline)
                                .padding(.leading)
                            Spacer()
                            Button(action: {
                                showClearClipboardAlert = true
                            }) {
                                Text("清空")
                                    .foregroundColor(.red)
                            }
                            .padding(.trailing)
                        }
                        .frame(height: 36)
                        .background(Color(.systemBackground))
                        Divider()
                        List {
                            ForEach(clipboardHistory.sorted(by: { $0.date > $1.date })) { item in
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.content)
                                            .font(.headline)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                        Text(historyDateString(item.date))
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.searchText = item.content
                                    self.isFirstResponder = true
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        if let idx = favorites.firstIndex(where: { $0.content == item.content }) {
                                            favorites.remove(at: idx)
                                            saveFavorites()
                                        } else {
                                            addFavorite(content: item.content)
                                        }
                                    } label: {
                                        Image(systemName: "pencil.line")
                                    }
                                    .tint(.orange)
                                    Button(role: .destructive) {
                                        if let index = clipboardHistory.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = clipboardHistory.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteClipboardHistory(at: offsets)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button {
                                        self.searchText = item.content
                                        self.isFirstResponder = true
                                    } label: {
                                        Text("插入")
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    Button {
                                        if let idx = favorites.firstIndex(where: { $0.content == item.content }) {
                                            favorites.remove(at: idx)
                                            saveFavorites()
                                        } else {
                                            addFavorite(content: item.content)
                                        }
                                    } label: {
                                        Text(favorites.contains(where: { $0.content == item.content }) ? "移除快捷" : "快捷")
                                        Image(systemName: "pencil.line")
                                    }
                                    Button(role: .destructive) {
                                        if let index = clipboardHistory.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = clipboardHistory.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteClipboardHistory(at: offsets)
                                        }
                                    } label: {
                                        Text("删除")
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteClipboardHistory)
                        }
                        .listStyle(PlainListStyle())
                    }
                    .alert(isPresented: $showClearClipboardAlert) {
                        Alert(title: Text("确认清空剪切板历史？"), message: nil, primaryButton: .destructive(Text("清空")) {
                            clearAllClipboardHistory()
                        }, secondaryButton: .cancel())
                    }
                } else if isShowingFavorites {
                    // 收藏夹纵向列表
                    VStack(spacing: 0) {
                        HStack {
                            Text("快捷短语")
                                .font(.headline)
                                .padding(.leading)
                            Spacer()
                            Button(action: {
                                showClearFavoritesAlert = true
                            }) {
                                Text("清空")
                                    .foregroundColor(.red)
                            }
                            .padding(.trailing)
                        }
                        .frame(height: 36)
                        .background(Color(.systemBackground))
                        Divider()
                        List {
                            ForEach(favorites.sorted(by: { $0.date > $1.date })) { item in
                                HStack(alignment: .center) {
                                    Text(item.content)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                    Spacer()
                                    // 追加按钮，直接调用controller
                                    Button(action: {
                                        self.searchText += item.content
                                    }) {
                                        Image(systemName: "text.append")
                                            .resizable()
                                            .frame(width: 22, height: 22)
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    self.searchText = item.content
                                    self.isFirstResponder = true
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        if let index = favorites.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = favorites.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteFavorite(at: offsets)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .tint(.red)
                                }
                                .contextMenu {
                                    Button {
                                        self.searchText = item.content
                                        self.isFirstResponder = true
                                    } label: {
                                        Text("插入")
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    Button {
                                        self.searchText += item.content
                                        self.isFirstResponder = true
                                    } label: {
                                        Text("追加")
                                        Image(systemName: "plus")
                                    }
                                    Button(role: .destructive) {
                                        if let index = favorites.sorted(by: { $0.date > $1.date }).firstIndex(where: { $0.id == item.id }) {
                                            let sorted = favorites.sorted(by: { $0.date > $1.date })
                                            let offsets = IndexSet(integer: index)
                                            deleteFavorite(at: offsets)
                                        }
                                    } label: {
                                        Text("删除")
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteFavorite)
                        }
                        .listStyle(PlainListStyle())
                    }
                    .alert(isPresented: $showClearFavoritesAlert) {
                        Alert(title: Text("确认清空收藏夹？"), message: nil, primaryButton: .destructive(Text("清空")) {
                            clearAllFavorites()
                        }, secondaryButton: .cancel())
                    }
                } else {
                    // 纵向列表只显示未隐藏且已排序的项
                    let visibleItems = searchItemSettings.filter { !$0.isHidden }
                    if showMainList {
                        List {
                            ForEach(visibleItems) { item in
                                let itemMode = itemModeDict[item.logo] ?? searchMode
                                Button(action: {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                    if itemMode == .app {
                                        if let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                            UIApplication.shared.open(url)
                                            addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                        } else if let webUrl = item.webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    } else {
                                        if let webUrl = item.webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        } else if let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                            UIApplication.shared.open(url)
                                            addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                        }
                                    }
                                }) {
                                    HStack {
                                        Group {
                                            if UIImage(named: item.logo) != nil {
                                                Image(item.logo)
                                                    .resizable()
                                            } else {
                                                Image(systemName: "app")
                                                .resizable()
                                            }
                                        }
                                        .frame(width: 32, height: 32)
                                        Text(item.name)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.leading, 12)
                                        // 新增：only+模式标识（只有一种模式时）
                                        if (item.appUrlScheme != nil && item.webUrl == nil) {
                                            HStack(spacing: 2) {
                                                Text("only")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                Image(systemName: "a.square.fill")
                                                    .resizable()
                                                    .frame(width: 16, height: 16)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        if (item.appUrlScheme == nil && item.webUrl != nil) {
                                            HStack(spacing: 2) {
                                                Text("only")
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                Image(systemName: "globe")
                                                    .resizable()
                                                    .frame(width: 16, height: 16)
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        // 只保留模式切换按钮（有两种模式时）
                                        if item.appUrlScheme != nil && item.webUrl != nil {
                                            Button(action: {
                                                itemModeDict[item.logo] = (itemMode == .app) ? .web : .app
                                            }) {
                                                Image(systemName: itemMode == .app ? "a.square.fill" : "globe")
                                                    .resizable()
                                                    .frame(width: 20, height: 20)
                                                    .foregroundColor(itemMode == .app ? .blue : .green)
                                            }
                                            .buttonStyle(BorderlessButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .contextMenu {
                                    Button {
                                        // Web 搜索
                                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if let webUrl = item.webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                                addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .web)
                                            }
                                        }
                                    } label: {
                                        let webKey = item.webKeyword
                                        Text(webKey != nil && !webKey!.isEmpty ? "Web搜索（\(webKey!)）" : "Web搜索")
                                        Image(systemName: "globe")
                                    }
                                    Button {
                                        // App 搜索
                                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                            UIApplication.shared.open(url)
                                            addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                        } else if let webUrl = item.webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        }
                                    } label: {
                                        let appKey = item.appKeyword
                                        Text(appKey != nil && !appKey!.isEmpty ? "App搜索（\(appKey!)）" : "App搜索")
                                        Image(systemName: "a.square.fill")
                                    }
                                    Button {
                                        // 移到最前
                                        if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                            let moved = searchItemSettings.remove(at: idx)
                                            searchItemSettings.insert(moved, at: 0)
                                            saveSearchItemSettings()
                                        }
                                    } label: {
                                        Text("移到最前")
                                        Image(systemName: "arrow.up.to.line")
                                    }
                                    Button {
                                        // 移到最后
                                        if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                            let moved = searchItemSettings.remove(at: idx)
                                            searchItemSettings.append(moved)
                                            saveSearchItemSettings()
                                        }
                                    } label: {
                                        Text("移到最后")
                                        Image(systemName: "arrow.down.to.line")
                                    }
                                    // 新增：隐藏/显示开关
                                    Toggle(isOn: Binding(
                                        get: { !(searchItemSettings.first(where: { $0.id == item.id })?.isHidden ?? false) },
                                        set: { newValue in
                                            if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                                searchItemSettings[idx].isHidden = !newValue
                                                saveSearchItemSettings()
                                            }
                                        })
                                    ) {
                                        Label("显示", systemImage: "eye")
                                    }
                                }
                                // .disabled(!isAvailable) // 修复：纵向列表无 isAvailable，直接移除
                            }
                        }
                        .listStyle(PlainListStyle())
                        .toolbar {
                            EditButton()
                        }
                    }
                    // else 不显示纵向列表
                }
            }
            Spacer() // 占位，把搜索框推到底部
            // 用ForEach(quickBarItems)顺序渲染快捷区
            ForEach(quickBarItems.filter { $0.isOn }) { bar in
                switch bar.id {
                case "logo":
                    let visibleItems = searchItemSettings.filter { !$0.isHidden }
                    HStack(spacing: 0) {
                        // 固定模式切换按钮（仅对选中logo生效）
                        Button(action: {
                            guard let logoId = selectedLogoId,
                                  let item = visibleItems.first(where: { $0.logo == logoId }) else { return }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            let currentMode = itemModeDict[logoId] ?? .app
                            itemModeDict[logoId] = (currentMode == .app) ? .web : .app
                        }) {
                            let currentMode = selectedLogoId.flatMap { itemModeDict[$0] } ?? .app
                            Image(systemName: currentMode == .app ? "a.square.fill" : "globe")
                                .resizable()
                                .frame(width: logoSizeType.size, height: logoSizeType.size)
                                .foregroundColor(currentMode == .app ? .blue : .green)
                        }
                        .contextMenu {
                            Button("小") { logoSizeType = .small; saveLogoSizeType() }
                            Button("中") { logoSizeType = .medium; saveLogoSizeType() }
                            Button("大") { logoSizeType = .large; saveLogoSizeType() }
                            Button("超大") { logoSizeType = .extraLarge; saveLogoSizeType() }
                            Divider()
                            Toggle("显示Logo横向滚动区", isOn: Binding(get: { showLogoBar }, set: { showLogoBar = $0; saveQuickBarSettings() }))
                            Toggle("显示历史记录横向滚动区", isOn: Binding(get: { showHistoryBar }, set: { showHistoryBar = $0; saveQuickBarSettings() }))
                            Toggle("显示收藏夹横向滚动区", isOn: Binding(get: { showFavoritesBar }, set: { showFavoritesBar = $0; saveQuickBarSettings() }))
                            Toggle("显示剪切板横向滚动区", isOn: Binding(get: { showClipboardBar }, set: { showClipboardBar = $0; saveQuickBarSettings() }))
                        }
                        .padding(.leading)
                        // logo 横向滚动区
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(visibleItems.indices, id: \ .self) { idx in
                                    let item = visibleItems[idx]
                                    let mode = itemModeDict[item.logo] ?? .app
                                    let isAvailable = (mode == .app && (item.appUrlScheme != nil || item.webUrl != nil)) || (mode == .web && item.webUrl != nil)
                                    Button(action: {
                                        guard isAvailable else { return }
                                        selectedLogoId = item.logo
                                        UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed.isEmpty {
                                            return
                                        }
                                        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                        if mode == .app {
                                            if let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                UIApplication.shared.open(url)
                                                addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                            } else if let webUrl = item.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                                }
                                            }
                                        } else if mode == .web, let webUrl = item.webUrl {
                                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                                addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .web)
                                            }
                                        }
                                    }) {
                                        Group {
                                            if UIImage(named: item.logo) != nil {
                                                Image(item.logo)
                                                    .resizable()
                                            } else {
                                                Image(systemName: mode == .app ? "app" : "globe")
                                                    .resizable()
                                            }
                                        }
                                        .frame(width: logoSizeType.size, height: logoSizeType.size)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .stroke(selectedLogoId == item.logo ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                        .opacity(isAvailable ? 1.0 : 0.3)
                                    }
                                    .contextMenu {
                                        Button {
                                            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            if let webUrl = item.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .web)
                                                }
                                            }
                                        } label: {
                                            let webKey = item.webKeyword
                                            Text(webKey != nil && !webKey!.isEmpty ? "Web搜索（\(webKey!)）" : "Web搜索")
                                            Image(systemName: "globe")
                                        }
                                        Button {
                                            let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            if let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                UIApplication.shared.open(url)
                                                addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                            } else if let webUrl = item.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: searchText, appName: item.name, appLogo: item.logo, mode: .app)
                                                }
                                            }
                                        } label: {
                                            let appKey = item.appKeyword
                                            Text(appKey != nil && !appKey!.isEmpty ? "App搜索（\(appKey!)）" : "App搜索")
                                            Image(systemName: "a.square.fill")
                                        }
                                        Button {
                                            if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                                let moved = searchItemSettings.remove(at: idx)
                                                searchItemSettings.insert(moved, at: 0)
                                                saveSearchItemSettings()
                                            }
                                        } label: {
                                            Text("移到最前")
                                            Image(systemName: "arrow.up.to.line")
                                        }
                                        Button {
                                            if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                                let moved = searchItemSettings.remove(at: idx)
                                                searchItemSettings.append(moved)
                                                saveSearchItemSettings()
                                            }
                                        } label: {
                                            Text("移到最后")
                                            Image(systemName: "arrow.down.to.line")
                                        }
                                        // 新增：隐藏/显示开关
                                        Toggle(isOn: Binding(
                                            get: { !(searchItemSettings.first(where: { $0.id == item.id })?.isHidden ?? false) },
                                            set: { newValue in
                                                if let idx = searchItemSettings.firstIndex(where: { $0.id == item.id }) {
                                                    searchItemSettings[idx].isHidden = !newValue
                                                    saveSearchItemSettings()
                                                }
                                            })
                                        ) {
                                            Label("显示", systemImage: "eye")
                                        }
                                    }
                                    .disabled(!isAvailable)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                case "history":
                    if !searchHistory.isEmpty && !isShowingSettings {
                        let dedupedHistory = searchHistory.sorted(by: { $0.date > $1.date }).enumerated().filter { idx, item in
                            if idx == 0 { return true }
                            let prev = searchHistory.sorted(by: { $0.date > $1.date })[idx - 1]
                            return item.keyword != prev.keyword
                        }.map { $0.element }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                Button(action: {
                                    isShowingHistory.toggle()
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    if isShowingHistory {
                                        isShowingClipboardList = false
                                        isShowingFavorites = false // 新增：关闭收藏夹弹窗
                                    }
                                }) {
                                    Image(systemName: incognitoMode ? "eye.slash.circle" : "clock.arrow.circlepath")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 28, height: 28)
                                        .foregroundColor(isShowingHistory ? .blue : .gray)
                                }
                                .contextMenu {
                                    Toggle(isOn: $incognitoMode) {
                                        Label("无痕搜索", systemImage: "eye.slash")
                                    }
                                    Button(role: .destructive) {
                                        showClearHistoryAlert = true
                                    } label: {
                                        Label("清空历史记录", systemImage: "trash")
                                    }
                                    Divider()
                                    Toggle("显示Logo横向滚动区", isOn: Binding(get: { showLogoBar }, set: { showLogoBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示历史记录横向滚动区", isOn: Binding(get: { showHistoryBar }, set: { showHistoryBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示收藏夹横向滚动区", isOn: Binding(get: { showFavoritesBar }, set: { showFavoritesBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示剪切板横向滚动区", isOn: Binding(get: { showClipboardBar }, set: { showClipboardBar = $0; saveQuickBarSettings() }))
                                }
                                ForEach(dedupedHistory) { item in
                                    Button(action: {
                                        self.searchText = item.keyword
                                        self.isFirstResponder = true
                                    }) {
                                        Text(item.keyword)
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(Color(.systemGray5))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 2)
                        }
                    }
                case "favorites":
                    if !favorites.isEmpty && !isShowingSettings {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                Button(action: {
                                    isShowingFavorites.toggle()
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    if isShowingFavorites { isShowingHistory = false; isShowingClipboardList = false }
                                }) {
                                    Image(systemName: "pencil.line")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                        .foregroundColor(isShowingFavorites ? .blue : .gray)
                                }
                                .contextMenu {
                                    Toggle("显示Logo横向滚动区", isOn: Binding(get: { showLogoBar }, set: { showLogoBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示历史记录横向滚动区", isOn: Binding(get: { showHistoryBar }, set: { showHistoryBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示收藏夹横向滚动区", isOn: Binding(get: { showFavoritesBar }, set: { showFavoritesBar = $0; saveQuickBarSettings() }))
                                    Toggle("显示剪切板横向滚动区", isOn: Binding(get: { showClipboardBar }, set: { showClipboardBar = $0; saveQuickBarSettings() }))
                                }
                                ForEach(favorites) { item in
                                    Button(action: {
                                        self.searchText = item.content
                                        self.isFirstResponder = true
                                    }) {
                                        Text(item.content)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(Color(.systemGray5))
                                            .clipShape(Capsule())
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 2)
                        }
                    }
                case "clipboard":
                    ClipboardHorizontalView(
                        clipboardHistory: clipboardHistory,
                        isShowingSettings: false, // 强制不受 isShowingSettings 影响
                        isShowingClipboardList: isShowingClipboardList,
                        setIsShowingClipboardList: { self.isShowingClipboardList = $0 },
                        isShowingHistory: isShowingHistory,
                        setIsShowingHistory: { self.isShowingHistory = $0 },
                        isShowingFavorites: isShowingFavorites,
                        setIsShowingFavorites: { self.isShowingFavorites = $0 },
                        recentClipboardTappedId: recentClipboardTappedId,
                        setRecentClipboardTappedId: { self.recentClipboardTappedId = $0 },
                        clipboardHasNew: clipboardHasNew,
                        setClipboardHasNew: { self.clipboardHasNew = $0 },
                        searchText: $searchText,
                        isFirstResponder: $isFirstResponder
                    )
                    .contextMenu {
                        Toggle("显示Logo横向滚动区", isOn: Binding(get: { showLogoBar }, set: { showLogoBar = $0; saveQuickBarSettings() }))
                        Toggle("显示历史记录横向滚动区", isOn: Binding(get: { showHistoryBar }, set: { showHistoryBar = $0; saveQuickBarSettings() }))
                        Toggle("显示收藏夹横向滚动区", isOn: Binding(get: { showFavoritesBar }, set: { showFavoritesBar = $0; saveQuickBarSettings() }))
                        Toggle("显示剪切板横向滚动区", isOn: Binding(get: { showClipboardBar }, set: { showClipboardBar = $0; saveQuickBarSettings() }))
                    }
                default:
                    EmptyView()
                }
            }

            // 语音按钮+搜索框
            HStack {
                Button(action: {
                    if speechRecognizer.isRecording {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        // 停止录音时音效
                        AudioServicesPlaySystemSound(1104)
                        speechRecognizer.stopRecording()
                    } else {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        // 开始录音时音效
                        AudioServicesPlaySystemSound(1103)
                        speechRecognizer.requestAuthorization { granted in
                            if granted {
                                speechRecognizer.startRecording { result, isFinal in
                                    print("语音识别 isFinal:", isFinal, "内容:", result)
                                    self.searchText = result
                                    // --- 超时自动判定逻辑 ---
                                    speechAutoJumpTimer?.invalidate()
                                    speechAutoJumpTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                        // 定时器触发时，自动执行搜指令跳转逻辑
                                        let pattern = #"^(?:用)?(.+?)(?:搜索|搜)(?:一下下|一下|下)?[，,、]?\s*([\s\S]+)$"#
                                        if let regex = try? NSRegularExpression(pattern: pattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.numberOfRanges == 3,
                                           let platformRange = Range(match.range(at: 1), in: result),
                                           let keywordRange = Range(match.range(at: 2), in: result) {
                                            let platform = String(result[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            let keyword = String(result[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                selectedLogoId = item.logo
                                                searchText = keyword
                                                isFirstResponder = false // 关闭键盘
                                                // 自动发起搜索
                                                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                let mode = itemModeDict[item.logo] ?? .app
                                                if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                } else if let webUrl = item.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                    }
                                                }
                                                speechRecognizer.stopRecording()
                                                speechAutoJumpTimer = nil
                                                return
                                            }
                                        }
                                    }
                                    // --- 下面是原有 over/over over/isFinal 跳转逻辑 ---
                                    // 优先检测 over over
                                    if overRecognitionMode == .double {
                                        let overOverPattern = #"(?i)\s*over\s+over\s*$"#
                                        if let regex = try? NSRegularExpression(pattern: overOverPattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.range.location != NSNotFound,
                                           let range = Range(match.range, in: result) {
                                            let beforeOver = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            self.searchText = beforeOver
                                            speechRecognizer.stopRecording()
                                            // 新增：优先尝试平台名提取
                                            let platformPattern = #"(?:用)?(.+?)(?:搜索|搜)\s*([\s\S]+)"#
                                            if let regex = try? NSRegularExpression(pattern: platformPattern),
                                               let match = regex.firstMatch(in: beforeOver, range: NSRange(location: 0, length: beforeOver.utf16.count)),
                                               match.numberOfRanges == 3,
                                               let platformRange = Range(match.range(at: 1), in: beforeOver),
                                               let keywordRange = Range(match.range(at: 2), in: beforeOver) {
                                                let platform = String(beforeOver[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                let keyword = String(beforeOver[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                    selectedLogoId = item.logo
                                                    searchText = keyword
                                                    isFirstResponder = false
                                                    let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                    let mode = itemModeDict[item.logo] ?? .app
                                                    if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                    } else if let webUrl = item.webUrl {
                                                        let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                        if let url = URL(string: urlString) {
                                                            UIApplication.shared.open(url)
                                                            addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                        }
                                                    }
                                                    return
                                                }
                                            }
                                            // fallback: 只用当前选中的 logo
                                            let trimmed = beforeOver.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            startLiveActivity()
                                            let query = beforeOver.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            let app: UnifiedSearchItem
                                            let mode: SearchMode
                                            if let logoId = selectedLogoId, let idx = searchItemSettings.firstIndex(where: { $0.logo == logoId }) {
                                                app = searchItemSettings[idx]
                                                mode = itemModeDict[logoId] ?? .app
                                            } else {
                                                app = searchItemSettings.first!
                                                selectedLogoId = app.logo
                                                UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                                                mode = itemModeDict[app.logo] ?? .app
                                            }
                                            if mode == .app {
                                                if let scheme = app.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: beforeOver, appName: app.name, appLogo: app.logo, mode: .app)
                                                } else if let webUrl = app.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            } else if mode == .web, let webUrl = app.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                }
                                            }
                                            return
                                        }
                                    }
                                    // 再检测 over
                                    if overRecognitionMode == .single {
                                        let overPattern = #"(?i)\s*over\s*$"#
                                        if let regex = try? NSRegularExpression(pattern: overPattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.range.location != NSNotFound,
                                           let range = Range(match.range, in: result) {
                                            let beforeOver = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            self.searchText = beforeOver
                                            speechRecognizer.stopRecording()
                                            // 新增：优先尝试平台名提取
                                            let platformPattern = #"(?:用)?(.+?)(?:搜索|搜)\s*([\s\S]+)"#
                                            if let regex = try? NSRegularExpression(pattern: platformPattern),
                                               let match = regex.firstMatch(in: beforeOver, range: NSRange(location: 0, length: beforeOver.utf16.count)),
                                               match.numberOfRanges == 3,
                                               let platformRange = Range(match.range(at: 1), in: beforeOver),
                                               let keywordRange = Range(match.range(at: 2), in: beforeOver) {
                                                let platform = String(beforeOver[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                let keyword = String(beforeOver[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                    selectedLogoId = item.logo
                                                    searchText = keyword
                                                    isFirstResponder = false
                                                    let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                    let mode = itemModeDict[item.logo] ?? .app
                                                    if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                    } else if let webUrl = item.webUrl {
                                                        let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                        if let url = URL(string: urlString) {
                                                            UIApplication.shared.open(url)
                                                            addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                        }
                                                    }
                                                    return
                                                }
                                            }
                                            // fallback: 只用当前选中的 logo
                                            let trimmed = beforeOver.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            startLiveActivity()
                                            let query = beforeOver.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            let app: UnifiedSearchItem
                                            let mode: SearchMode
                                            if let logoId = selectedLogoId, let idx = searchItemSettings.firstIndex(where: { $0.logo == logoId }) {
                                                app = searchItemSettings[idx]
                                                mode = itemModeDict[logoId] ?? .app
                                            } else {
                                                app = searchItemSettings.first!
                                                selectedLogoId = app.logo
                                                UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                                                mode = itemModeDict[app.logo] ?? .app
                                            }
                                            if mode == .app {
                                                if let scheme = app.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: beforeOver, appName: app.name, appLogo: app.logo, mode: .app)
                                                } else if let webUrl = app.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            } else if mode == .web, let webUrl = app.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                }
                                            }
                                            return
                                        }
                                    }
                                    // 其它 isFinal 逻辑
                                    if isFinal {
                                        let pattern = #"^(?:用)?(.+?)(?:搜索|搜)(?:一下下|一下|下)?[，,、]?\s*([\s\S]+)$"#
                                        if let regex = try? NSRegularExpression(pattern: pattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.numberOfRanges == 3,
                                           let platformRange = Range(match.range(at: 1), in: result),
                                           let keywordRange = Range(match.range(at: 2), in: result) {
                                            let platform = String(result[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            let keyword = String(result[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                selectedLogoId = item.logo
                                                searchText = keyword
                                                isFirstResponder = false // 关闭键盘
                                                // 自动发起搜索
                                                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                let mode = itemModeDict[item.logo] ?? .app
                                                if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                } else if let webUrl = item.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                    }
                                                }
                                                speechRecognizer.stopRecording()
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }) {
                    Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic")
                        .foregroundColor(speechRecognizer.isRecording ? .red : .gray)
                        .font(.system(size: 22))
                }
                .padding(.leading, 8)
                .padding(.trailing, 4)
                .frame(height: 44)
                .contextMenu {
                    Button(action: {
                        overRecognitionMode = .off
                        saveOverRecognitionMode()
                    }) {
                        Label("关闭识别结尾词", systemImage: overRecognitionMode == .off ? "checkmark" : "")
                    }
                    Button(action: {
                        overRecognitionMode = .single
                        saveOverRecognitionMode()
                    }) {
                        Label("识别结尾词over", systemImage: overRecognitionMode == .single ? "checkmark" : "")
                    }
                    Button(action: {
                        overRecognitionMode = .double
                        saveOverRecognitionMode()
                    }) {
                        Label("识别结尾词over over", systemImage: overRecognitionMode == .double ? "checkmark" : "")
                    }
                    // 新增：启动时自动语音开关
                    Toggle(isOn: $autoStartVoiceOnLaunch) {
                        Label("启动时打开语音", systemImage: "mic")
                    }
                    .onChange(of: autoStartVoiceOnLaunch) { _ in
                        saveAutoStartVoiceOnLaunch()
                    }
                }
                SearchBar(
                    text: $searchText,
                    placeholder: "搜索...",
                    onSearch: {
                        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        startLiveActivity()
                        let query = searchText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        let app: UnifiedSearchItem
                        let mode: SearchMode
                        if let logoId = selectedLogoId, let idx = searchItemSettings.firstIndex(where: { $0.logo == logoId }) {
                            app = searchItemSettings[idx]
                            mode = itemModeDict[logoId] ?? .app
                        } else {
                            app = searchItemSettings.first!
                            selectedLogoId = app.logo
                            UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                            mode = itemModeDict[app.logo] ?? .app
                        }
                        if mode == .app {
                            if let scheme = app.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                UIApplication.shared.open(url)
                                addSearchHistory(keyword: searchText, appName: app.name, appLogo: app.logo, mode: .app)
                            } else if let webUrl = app.webUrl {
                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                if let url = URL(string: urlString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                        } else if mode == .web, let webUrl = app.webUrl {
                            let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                            if let url = URL(string: urlString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    },
                    isFirstResponder: $isFirstResponder,
                    showCloseButton: isKeyboardVisible, // 只在键盘弹出时显示
                    onClose: {
                        self.isFirstResponder = false // 收起键盘
                    }
                )
                .frame(height: 44)
            }
            .padding([.horizontal, .bottom]) // 边距
        }
        .padding(.top) // 只保留顶部内边距
        // 监听输入内容变化，切换设置/搜索列表
        .onChange(of: searchText) { newValue in
            // 关键词自动切换逻辑
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = searchItemSettings.first(where: { $0.appKeyword != nil && newValue == $0.appKeyword! + " " }) {
                // 匹配App关键词
                selectedLogoId = match.logo
                itemModeDict[match.logo] = .app
                searchText = ""
                isFirstResponder = true
                return
            } else if let match = searchItemSettings.first(where: { $0.webKeyword != nil && newValue == $0.webKeyword! + " " }) {
                // 匹配Web关键词
                selectedLogoId = match.logo
                itemModeDict[match.logo] = .web
                searchText = ""
                isFirstResponder = true
                return
            }
            // 只要不是"设置"或"设置"后无内容，自动切回App搜索列表
            if newValue == "设置" || newValue == "设置 " || newValue == "设置\n" {
                isShowingSettings = true
                isShowingClipboardList = false
            } else {
                isShowingSettings = false
            }
        }
        // 合并所有设置弹窗为一个 confirmationDialog
        .confirmationDialog("设置", isPresented: .constant(settingSheetType != .none), titleVisibility: .visible) {
            if settingSheetType == .color {
                Button("跟随系统") { colorSchemeSetting = .system; settingSheetType = .none }
                Button("浅色") { colorSchemeSetting = .light; settingSheetType = .none }
                Button("深色") { colorSchemeSetting = .dark; settingSheetType = .none }
                Button("取消", role: .cancel) { settingSheetType = .none }
            } else if settingSheetType == .logoSize {
                Button("小") { logoSizeType = .small; saveLogoSizeType(); settingSheetType = .none }
                Button("中") { logoSizeType = .medium; saveLogoSizeType(); settingSheetType = .none }
                Button("大") { logoSizeType = .large; saveLogoSizeType(); settingSheetType = .none }
                Button("超大") { logoSizeType = .extraLarge; saveLogoSizeType(); settingSheetType = .none } // 新增
                Button("取消", role: .cancel) { settingSheetType = .none }
            } else if settingSheetType == .defaultApp {
                ForEach(defaultUnifiedList, id: \ .name) { app in
                    Button(app.name) {
                        defaultSearchAppName = app.name
                        saveDefaultSearchApp()
                        settingSheetType = .none
                    }
                }
                Button("取消", role: .cancel) { settingSheetType = .none }
            } else if settingSheetType == .defaultBrowser {
                ForEach(WebBrowserType.allCases, id: \ .rawValue) { type in
                    Button(type.displayName) {
                        defaultWebBrowser = type
                        saveDefaultWebBrowser()
                        settingSheetType = .none
                    }
                }
                Button("取消", role: .cancel) { settingSheetType = .none }
            } else if settingSheetType == .overRecognition {
                ForEach(OverRecognitionMode.allCases, id: \ .rawValue) { mode in
                    Button(mode.displayName) {
                        overRecognitionMode = mode
                        saveOverRecognitionMode()
                        settingSheetType = .none
                    }
                }
                Button("取消", role: .cancel) { settingSheetType = .none }
            } else if settingSheetType == .appIcon {
                Button("默认") { changeAppIcon(nil); settingSheetType = .none }
                Button("极简") { changeAppIcon("minimal"); settingSheetType = .none }
                Button("取消", role: .cancel) { settingSheetType = .none }
            }
        }
        // 根据设置切换颜色模式
        .preferredColorScheme(
            colorSchemeSetting == .system ? nil : (colorSchemeSetting == .light ? .light : .dark)
        )
        // 恢复 onAppear，初始化appList并自动聚焦输入框
        .onAppear {
            loadDefaultSearchApp()
            loadSearchHistory()
            loadClipboardHistory()
            loadFavorites()
            loadLogoSizeType()
            loadSearchItemSettings()
            loadQuickBarItems() // 替换原loadQuickBarSettings
            loadAutoFocusOnLaunch()
            loadShowMainList()
            // 新增：加载自动语音开关
            loadAutoStartVoiceOnLaunch()
            let visibleItems = searchItemSettings.filter { !$0.isHidden }
            if let lastLogoId = UserDefaults.standard.string(forKey: lastSelectedLogoIdKey),
               visibleItems.contains(where: { $0.logo == lastLogoId }) {
                selectedLogoId = lastLogoId
            } else {
                selectedLogoId = visibleItems.first?.logo
            }
            if autoFocusOnLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isFirstResponder = true
                }
            }
            // 新增：自动语音（延迟到searchItemSettings加载后再启动）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if autoStartVoiceOnLaunch {
                    if !speechRecognizer.isRecording {
                        speechRecognizer.requestAuthorization { granted in
                            if granted {
                                AudioServicesPlaySystemSound(1103)
                                speechRecognizer.startRecording { result, isFinal in
                                    print("语音识别 isFinal:", isFinal, "内容:", result)
                                    self.searchText = result
                                    // --- 超时自动判定逻辑 ---
                                    speechAutoJumpTimer?.invalidate()
                                    speechAutoJumpTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                        // 定时器触发时，自动执行搜指令跳转逻辑
                                        let pattern = #"^(?:用)?(.+?)(?:搜索|搜)(?:一下下|一下|下)?[，,、]?\s*([\s\S]+)$"#
                                        if let regex = try? NSRegularExpression(pattern: pattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.numberOfRanges == 3,
                                           let platformRange = Range(match.range(at: 1), in: result),
                                           let keywordRange = Range(match.range(at: 2), in: result) {
                                            let platform = String(result[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            let keyword = String(result[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                selectedLogoId = item.logo
                                                searchText = keyword
                                                isFirstResponder = false // 关闭键盘
                                                // 自动发起搜索
                                                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                let mode = itemModeDict[item.logo] ?? .app
                                                if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                } else if let webUrl = item.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                    }
                                                }
                                                speechRecognizer.stopRecording()
                                                speechAutoJumpTimer = nil
                                                return
                                            }
                                        }
                                    }
                                    // --- 下面是原有 over/over over/isFinal 跳转逻辑 ---
                                    // 优先检测 over over
                                    if overRecognitionMode == .double {
                                        let overOverPattern = #"(?i)\s*over\s+over\s*$"#
                                        if let regex = try? NSRegularExpression(pattern: overOverPattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.range.location != NSNotFound,
                                           let range = Range(match.range, in: result) {
                                            let beforeOver = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            self.searchText = beforeOver
                                            speechRecognizer.stopRecording()
                                            // 新增：优先尝试平台名提取
                                            let platformPattern = #"(?:用)?(.+?)(?:搜索|搜)\s*([\s\S]+)"#
                                            if let regex = try? NSRegularExpression(pattern: platformPattern),
                                               let match = regex.firstMatch(in: beforeOver, range: NSRange(location: 0, length: beforeOver.utf16.count)),
                                               match.numberOfRanges == 3,
                                               let platformRange = Range(match.range(at: 1), in: beforeOver),
                                               let keywordRange = Range(match.range(at: 2), in: beforeOver) {
                                                let platform = String(beforeOver[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                let keyword = String(beforeOver[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                    selectedLogoId = item.logo
                                                    searchText = keyword
                                                    isFirstResponder = false
                                                    let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                    let mode = itemModeDict[item.logo] ?? .app
                                                    if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                    } else if let webUrl = item.webUrl {
                                                        let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                        if let url = URL(string: urlString) {
                                                            UIApplication.shared.open(url)
                                                            addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                        }
                                                    }
                                                    return
                                                }
                                            }
                                            // fallback: 只用当前选中的 logo
                                            let trimmed = beforeOver.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            startLiveActivity()
                                            let query = beforeOver.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            let app: UnifiedSearchItem
                                            let mode: SearchMode
                                            if let logoId = selectedLogoId, let idx = searchItemSettings.firstIndex(where: { $0.logo == logoId }) {
                                                app = searchItemSettings[idx]
                                                mode = itemModeDict[logoId] ?? .app
                                            } else {
                                                app = searchItemSettings.first!
                                                selectedLogoId = app.logo
                                                UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                                                mode = itemModeDict[app.logo] ?? .app
                                            }
                                            if mode == .app {
                                                if let scheme = app.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: beforeOver, appName: app.name, appLogo: app.logo, mode: .app)
                                                } else if let webUrl = app.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            } else if mode == .web, let webUrl = app.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                }
                                            }
                                            return
                                        }
                                    }
                                    // 再检测 over
                                    if overRecognitionMode == .single {
                                        let overPattern = #"(?i)\s*over\s*$"#
                                        if let regex = try? NSRegularExpression(pattern: overPattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.range.location != NSNotFound,
                                           let range = Range(match.range, in: result) {
                                            let beforeOver = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            self.searchText = beforeOver
                                            speechRecognizer.stopRecording()
                                            // 新增：优先尝试平台名提取
                                            let platformPattern = #"(?:用)?(.+?)(?:搜索|搜)\s*([\s\S]+)"#
                                            if let regex = try? NSRegularExpression(pattern: platformPattern),
                                               let match = regex.firstMatch(in: beforeOver, range: NSRange(location: 0, length: beforeOver.utf16.count)),
                                               match.numberOfRanges == 3,
                                               let platformRange = Range(match.range(at: 1), in: beforeOver),
                                               let keywordRange = Range(match.range(at: 2), in: beforeOver) {
                                                let platform = String(beforeOver[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                let keyword = String(beforeOver[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                                if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                    selectedLogoId = item.logo
                                                    searchText = keyword
                                                    isFirstResponder = false
                                                    let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                    let mode = itemModeDict[item.logo] ?? .app
                                                    if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                    } else if let webUrl = item.webUrl {
                                                        let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                        if let url = URL(string: urlString) {
                                                            UIApplication.shared.open(url)
                                                            addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                        }
                                                    }
                                                    return
                                                }
                                            }
                                            // fallback: 只用当前选中的 logo
                                            let trimmed = beforeOver.trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !trimmed.isEmpty else { return }
                                            startLiveActivity()
                                            let query = beforeOver.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                            let app: UnifiedSearchItem
                                            let mode: SearchMode
                                            if let logoId = selectedLogoId, let idx = searchItemSettings.firstIndex(where: { $0.logo == logoId }) {
                                                app = searchItemSettings[idx]
                                                mode = itemModeDict[logoId] ?? .app
                                            } else {
                                                app = searchItemSettings.first!
                                                selectedLogoId = app.logo
                                                UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
                                                mode = itemModeDict[app.logo] ?? .app
                                            }
                                            if mode == .app {
                                                if let scheme = app.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: beforeOver, appName: app.name, appLogo: app.logo, mode: .app)
                                                } else if let webUrl = app.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            } else if mode == .web, let webUrl = app.webUrl {
                                                let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                if let url = URL(string: urlString) {
                                                    UIApplication.shared.open(url)
                                                }
                                            }
                                            return
                                        }
                                    }
                                    // 其它 isFinal 逻辑
                                    if isFinal {
                                        let pattern = #"^(?:用)?(.+?)(?:搜索|搜)(?:一下下|一下|下)?[，,、]?\s*([\s\S]+)$"#
                                        if let regex = try? NSRegularExpression(pattern: pattern),
                                           let match = regex.firstMatch(in: result, range: NSRange(location: 0, length: result.utf16.count)),
                                           match.numberOfRanges == 3,
                                           let platformRange = Range(match.range(at: 1), in: result),
                                           let keywordRange = Range(match.range(at: 2), in: result) {
                                            let platform = String(result[platformRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            let keyword = String(result[keywordRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                                            if let item = searchItemSettings.first(where: { platform.contains($0.name) || $0.name.contains(platform) }) {
                                                selectedLogoId = item.logo
                                                searchText = keyword
                                                isFirstResponder = false // 关闭键盘
                                                // 自动发起搜索
                                                let query = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                                                let mode = itemModeDict[item.logo] ?? .app
                                                if mode == .app, let scheme = item.appUrlScheme, let url = URL(string: scheme.replacingOccurrences(of: "{query}", with: query)) {
                                                    UIApplication.shared.open(url)
                                                    addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .app)
                                                } else if let webUrl = item.webUrl {
                                                    let urlString = defaultWebBrowser.schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: query)
                                                    if let url = URL(string: urlString) {
                                                        UIApplication.shared.open(url)
                                                        addSearchHistory(keyword: keyword, appName: item.name, appLogo: item.logo, mode: .web)
                                                    }
                                                }
                                                speechRecognizer.stopRecording()
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            requestNotificationPermission()
            checkClipboardOnce()
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                self.isKeyboardVisible = true
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                self.isKeyboardVisible = false
            }
            loadOverRecognitionMode()
            updateCurrentAppIconDisplayName() // 新增：同步当前图标显示名
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                checkClipboardOnce()
            } else if newPhase == .background {
                // 只在没有活动时才新建
                if Activity<ReadytoReachAttributes>.activities.isEmpty {
                    let attributes = ReadytoReachAttributes(title: "后台搜索")
                    let initialState = ReadytoReachAttributes.ContentState(progress: 0.0, message: "开始搜索")
                    do {
                        let activity = try Activity<ReadytoReachAttributes>.request(
                            attributes: attributes,
                            contentState: initialState,
                            pushType: nil
                        )
                        print("Live Activity started: \(activity.id)")
                    } catch {
                        print("无法启动Live Activity: \(error)")
                    }
                } else {
                    print("已有Live Activity，无需重复创建")
                }
            }
        }
    }

    // 请求语音识别权限并开始识别
    // func requestSpeechAuthAndStart() { ... }

    // 开始语音识别
    // func startRecording() { ... }

    // 停止语音识别
    // func stopRecording() { ... }

    // 拖拽排序的处理函数（Web搜索）
    func moveUnifiedList(from source: IndexSet, to destination: Int) {
        // unifiedList.move(fromOffsets: source, toOffset: destination) // 已废弃
        saveUnifiedListOrder()
    }

    // 保存 unifiedList 顺序到 UserDefaults
    func saveUnifiedListOrder() {
        let nameOrder = searchItemSettings.map { $0.name }
        UserDefaults.standard.set(nameOrder, forKey: unifiedListOrderKey)
    }
    // 已废弃unifiedList相关函数

    // 播放系统音效的函数，soundID 1103=开始录音，1104=结束录音
    // func playSystemSound(_ soundID: SystemSoundID) { ... }

    // 保存默认搜索App到UserDefaults
    func saveDefaultSearchApp() {
        UserDefaults.standard.set(defaultSearchAppName, forKey: defaultSearchAppKey)
    }
    // 加载默认搜索App
    func loadDefaultSearchApp() {
        if let name = UserDefaults.standard.string(forKey: defaultSearchAppKey),
           defaultUnifiedList.contains(where: { $0.name == name }) {
            defaultSearchAppName = name
        } else {
            defaultSearchAppName = defaultUnifiedList.first?.name ?? "小红书"
        }
    }
    // 记录历史
    func addSearchHistory(keyword: String, appName: String, appLogo: String, mode: SearchMode) {
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if incognitoMode { return } // 新增：无痕模式下不记录历史
        let item = SearchHistoryItem(date: Date(), keyword: keyword, appName: appName, appLogo: appLogo, mode: mode)
        searchHistory.insert(item, at: 0)
        // 最多保存50条
        if searchHistory.count > 50 {
            searchHistory = Array(searchHistory.prefix(50))
        }
        // 持久化
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: searchHistoryKey)
        }
        // 同步高亮app
        if let idx = searchItemSettings.firstIndex(where: { $0.name == appName }) {
            selectedLogoId = searchItemSettings[idx].logo
            UserDefaults.standard.set(selectedLogoId, forKey: lastSelectedLogoIdKey)
        }
    }
    // 加载历史
    func loadSearchHistory() {
        if let data = UserDefaults.standard.data(forKey: searchHistoryKey),
           let arr = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) {
            searchHistory = arr
        }
    }
    // 删除历史记录
    func deleteHistory(at offsets: IndexSet) {
        // 由于历史是按时间倒序展示，需先排序再删除
        var sorted = searchHistory.sorted(by: { $0.date > $1.date })
        sorted.remove(atOffsets: offsets)
        searchHistory = sorted.sorted(by: { $0.date > $1.date })
        // 持久化
        if let data = try? JSONEncoder().encode(searchHistory) {
            UserDefaults.standard.set(data, forKey: searchHistoryKey)
        }
        if searchHistory.isEmpty {
            isShowingHistory = false
        }
    }
    // 清空全部历史
    func clearAllHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: searchHistoryKey)
        isShowingHistory = false
    }
    // 日期格式化
    func historyDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // 剪切板历史相关方法
    func loadClipboardHistory() {
        if let data = UserDefaults.standard.data(forKey: clipboardHistoryKey),
           let arr = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data) {
            clipboardHistory = arr
        }
    }
    func saveClipboardHistory() {
        if let data = try? JSONEncoder().encode(clipboardHistory) {
            UserDefaults.standard.set(data, forKey: clipboardHistoryKey)
        }
    }
    func addClipboardHistory(content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // 去重（只保留最新一条）
        clipboardHistory.removeAll { $0.content == content }
        clipboardHistory.insert(ClipboardHistoryItem(content: content, date: Date()), at: 0)
        if clipboardHistory.count > 20 {
            clipboardHistory = Array(clipboardHistory.prefix(20))
        }
        saveClipboardHistory()
        clipboardHasNew = true
    }
    // 删除单条剪切板历史
    func deleteClipboardHistory(at offsets: IndexSet) {
        var sorted = clipboardHistory.sorted(by: { $0.date > $1.date })
        sorted.remove(atOffsets: offsets)
        clipboardHistory = sorted.sorted(by: { $0.date > $1.date })
        saveClipboardHistory()
        if clipboardHistory.isEmpty {
            isShowingClipboardList = false
        }
    }
    // 清空全部剪切板历史
    func clearAllClipboardHistory() {
        clipboardHistory = []
        UserDefaults.standard.removeObject(forKey: clipboardHistoryKey)
        isShowingClipboardList = false
    }
    // 收藏夹相关方法
    func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let arr = try? JSONDecoder().decode([FavoriteItem].self, from: data) {
            favorites = arr
        }
    }
    func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
    func addFavorite(content: String) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // 去重（只保留最新一条）
        favorites.removeAll { $0.content == content }
        favorites.insert(FavoriteItem(content: content, date: Date()), at: 0)
        if favorites.count > 50 {
            favorites = Array(favorites.prefix(50))
        }
        saveFavorites()
    }
    func deleteFavorite(at offsets: IndexSet) {
        var sorted = favorites.sorted(by: { $0.date > $1.date })
        sorted.remove(atOffsets: offsets)
        favorites = sorted.sorted(by: { $0.date > $1.date })
        saveFavorites()
        if favorites.isEmpty {
            isShowingFavorites = false
        }
    }
    // 只在App进入前台时检测一次剪切板
    func checkClipboardOnce() {
        let current = UIPasteboard.general.string ?? ""
        guard !current.isEmpty else { return }
        // 如果历史中没有这条内容才添加
        if clipboardHistory.first?.content != current {
            addClipboardHistory(content: current)
        }
    }
    // 保存默认Web浏览器
    func saveDefaultWebBrowser() {
        UserDefaults.standard.set(defaultWebBrowser.rawValue, forKey: defaultWebBrowserKey)
    }
    // 加载默认Web浏览器
    func loadDefaultWebBrowser() {
        if let raw = UserDefaults.standard.string(forKey: defaultWebBrowserKey),
           let type = WebBrowserType(rawValue: raw) {
            defaultWebBrowser = type
        } else {
            defaultWebBrowser = .chrome
        }
    }
    // 新增：保存logo大小设置
    func saveLogoSizeType() {
        UserDefaults.standard.set(logoSizeType.rawValue, forKey: logoSizeTypeKey)
    }
    // 新增：加载logo大小设置
    func loadLogoSizeType() {
        if let raw = UserDefaults.standard.string(forKey: logoSizeTypeKey),
           let type = LogoSizeType(rawValue: raw) {
            logoSizeType = type
        } else {
            logoSizeType = .extraLarge
        }
    }
    func clearAllFavorites() {
        favorites = []
        UserDefaults.standard.removeObject(forKey: favoritesKey)
        isShowingFavorites = false
    }
    // 新增：搜索项管理持久化
    func saveSearchItemSettings() {
        if let data = try? JSONEncoder().encode(searchItemSettings) {
            UserDefaults.standard.set(data, forKey: searchItemSettingsKey)
        }
        // 新增：同步未隐藏logo顺序到App Group
        // 按照 searchItemSettings 的顺序，只包含未隐藏的项
        let visibleLogoOrder = searchItemSettings.filter { !$0.isHidden }.map { $0.logo }
        print("🔧 保存搜索项设置 - 未隐藏的图标数量: \(visibleLogoOrder.count)")
        print("🔧 未隐藏的图标列表: \(visibleLogoOrder)")
        
        if let groupDefaults = UserDefaults(suiteName: "group.com.zisa.ReadytoReach") {
            groupDefaults.set(visibleLogoOrder, forKey: "AppLogoOrderKey")
            // 强制同步，确保数据立即写入
            groupDefaults.synchronize()
            
            // 验证写入的数据
            if let savedOrder = groupDefaults.array(forKey: "AppLogoOrderKey") as? [String] {
                print("✅ App Group中保存的图标数量: \(savedOrder.count)")
                print("✅ App Group中保存的图标列表: \(savedOrder)")
            }
            
            // 同步完整的搜索项设置到App Group，供Widget Extension使用
            if let data = try? JSONEncoder().encode(searchItemSettings) {
                groupDefaults.set(data, forKey: "SearchItemSettingsKey")
                groupDefaults.synchronize()
            }
            // 同步搜索模式信息
            for (logo, mode) in itemModeDict {
                groupDefaults.set(mode.rawValue, forKey: "ItemMode_\(logo)")
            }
            // 同步默认浏览器设置
            groupDefaults.set(defaultWebBrowser.rawValue, forKey: "DefaultWebBrowserKey")
            groupDefaults.synchronize()
        } else {
            print("❌ 无法访问App Group UserDefaults")
        }
        // 新增：主动刷新Widget
        WidgetCenter.shared.reloadAllTimelines()
        // 更新正在运行的 Live Activity，使其显示最新的顺序
        updateLiveActivityOrder()
    }
    
    // 新增：更新 Live Activity 的顺序显示
    func updateLiveActivityOrder() {
        Task {
            // 通过更新 Live Activity 的状态来触发 UI 刷新
            // 即使内容不变，更新操作也会触发 UI 重新渲染
            let activities = Activity<ReadytoReachAttributes>.activities
            print("🔄 更新 Live Activity - 当前活动数量: \(activities.count)")
            for activity in activities {
                let currentState = activity.contentState
                // 使用相同的状态更新，触发 UI 刷新以读取最新的顺序
                await activity.update(using: currentState)
                print("✅ Live Activity 已更新")
            }
        }
    }
    func loadSearchItemSettings() {
        if let data = UserDefaults.standard.data(forKey: searchItemSettingsKey),
           let arr = try? JSONDecoder().decode([UnifiedSearchItem].self, from: data) {
            searchItemSettings = arr
        } else {
            searchItemSettings = defaultUnifiedList
        }
        // 加载后立即同步到App Group，确保Widget Extension可以访问
        if let groupDefaults = UserDefaults(suiteName: "group.com.zisa.ReadytoReach") {
            if let data = try? JSONEncoder().encode(searchItemSettings) {
                groupDefaults.set(data, forKey: "SearchItemSettingsKey")
            }
            let visibleLogoOrder = searchItemSettings.filter { !$0.isHidden }.map { $0.logo }
            groupDefaults.set(visibleLogoOrder, forKey: "AppLogoOrderKey")
            // 强制同步，确保数据立即写入
            groupDefaults.synchronize()
            print("📥 加载搜索项设置 - 未隐藏的图标数量: \(visibleLogoOrder.count)")
            // 同步搜索模式信息
            for (logo, mode) in itemModeDict {
                groupDefaults.set(mode.rawValue, forKey: "ItemMode_\(logo)")
            }
            // 同步默认浏览器设置
            groupDefaults.set(defaultWebBrowser.rawValue, forKey: "DefaultWebBrowserKey")
            groupDefaults.synchronize()
        }
    }
    // 快捷操作区显示设置持久化
    func saveQuickBarSettings() {
        let dict: [String: Bool] = [
            "logo": showLogoBar,
            "history": showHistoryBar,
            "favorites": showFavoritesBar,
            "clipboard": showClipboardBar
        ]
        UserDefaults.standard.set(dict, forKey: quickBarSettingsKey)
    }
    func loadQuickBarSettings() {
        if let dict = UserDefaults.standard.dictionary(forKey: quickBarSettingsKey) as? [String: Bool] {
            showLogoBar = dict["logo"] ?? true
            showHistoryBar = dict["history"] ?? true
            showFavoritesBar = dict["favorites"] ?? true
            showClipboardBar = dict["clipboard"] ?? true
        }
    }
    func changeAppIcon(_ iconName: String?) {
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                print("切换图标失败: \(error.localizedDescription)")
            } else {
                updateCurrentAppIconDisplayName()
            }
        }
    }
    func updateCurrentAppIconDisplayName() {
        if let name = UIApplication.shared.alternateIconName {
            if name == "minimal" { currentAppIconDisplayName = "极简" }
            else { currentAppIconDisplayName = name }
        } else {
            currentAppIconDisplayName = "默认"
        }
    }
}

// 新增：UISearchBar的UIViewRepresentable封装
struct SearchBar: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSearch: (() -> Void)? = nil
    @Binding var isFirstResponder: Bool
    var showCloseButton: Bool = false // 新增
    var onClose: (() -> Void)? = nil  // 新增

    class Coordinator: NSObject, UISearchBarDelegate {
        var parent: SearchBar
        init(_ parent: SearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.onSearch?()
        }
        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.isFirstResponder = false
            parent.onClose?()
        }
        // 新增：同步isFirstResponder，保证点击输入框后可正常弹出键盘
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            parent.isFirstResponder = true
        }
        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            parent.isFirstResponder = false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar()
        searchBar.delegate = context.coordinator
        searchBar.placeholder = placeholder
        searchBar.returnKeyType = .search
        searchBar.autocapitalizationType = .none
        searchBar.showsCancelButton = showCloseButton
        // 去除上下分割线和背景色
        searchBar.backgroundImage = UIImage()
        searchBar.backgroundColor = .clear
        searchBar.barTintColor = .clear
        searchBar.layer.masksToBounds = true
        // 只显示图标，无文字
        DispatchQueue.main.async {
            if let cancelButton = searchBar.value(forKey: "cancelButton") as? UIButton {
                cancelButton.setTitle("", for: .normal)
                let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
                let image = UIImage(systemName: "xmark", withConfiguration: config)
                cancelButton.setImage(image, for: .normal)
                cancelButton.tintColor = .gray
            }
        }
        return searchBar
    }
    func updateUIView(_ uiView: UISearchBar, context: Context) {
        uiView.text = text
        uiView.showsCancelButton = showCloseButton
        // 去除上下分割线和背景色
        uiView.backgroundImage = UIImage()
        uiView.backgroundColor = .clear
        uiView.barTintColor = .clear
        uiView.layer.masksToBounds = true
        // 自动聚焦/失焦
        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
        if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
        // 只显示图标，无文字
        DispatchQueue.main.async {
            if let cancelButton = uiView.value(forKey: "cancelButton") as? UIButton {
                cancelButton.setTitle("", for: .normal)
                let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
                let image = UIImage(systemName: "xmark", withConfiguration: config)
                cancelButton.setImage(image, for: .normal)
                cancelButton.tintColor = .gray
            }
        }
    }
}

// 新增：剪切板横向滚动区子组件
struct ClipboardHorizontalView: View {
    let clipboardHistory: [ContentView.ClipboardHistoryItem]
    let isShowingSettings: Bool // 兼容参数，但不再用
    let isShowingClipboardList: Bool
    let setIsShowingClipboardList: (Bool) -> Void
    let isShowingHistory: Bool
    let setIsShowingHistory: (Bool) -> Void
    let isShowingFavorites: Bool
    let setIsShowingFavorites: (Bool) -> Void
    let recentClipboardTappedId: UUID?
    let setRecentClipboardTappedId: (UUID) -> Void
    let clipboardHasNew: Bool
    let setClipboardHasNew: (Bool) -> Void
    @Binding var searchText: String
    @Binding var isFirstResponder: Bool

    var body: some View {
        let sortedClipboard = clipboardHistory.sorted(by: { $0.date > $1.date })
        let latestId = sortedClipboard.first?.id
        if !sortedClipboard.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 剪切板按钮
                    Button(action: {
                        setIsShowingClipboardList(!isShowingClipboardList)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        if !isShowingClipboardList {
                            setIsShowingHistory(false)
                            setIsShowingFavorites(false)
                        }
                    }) {
                        Image(systemName: "doc.on.clipboard")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundColor(isShowingClipboardList ? .blue : .gray)
                    }
                    ForEach(sortedClipboard) { item in
                        Button(action: {
                            searchText = item.content
                            isFirstResponder = true
                            setRecentClipboardTappedId(item.id)
                            setClipboardHasNew(false)
                        }) {
                            Text(item.content)
                                .font(.subheadline)
                                .foregroundColor(
                                    (clipboardHasNew && item.id == latestId) ? .blue : .gray
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 2)
            }
        }
    }
}

#Preview {
    ContentView()
}

// 启动实时活动
func startLiveActivity() {
    let attributes = ReadytoReachAttributes(title: "搜索进度")
    let initialState = ReadytoReachAttributes.ContentState(progress: 0.0, message: "开始搜索")
    do {
        let activity = try Activity<ReadytoReachAttributes>.request(
            attributes: attributes,
            contentState: initialState,
            pushType: nil
        )
        print("Live Activity started: \(activity.id)")
    } catch {
        print("无法启动Live Activity: \(error)")
    }
}

// 更新实时活动
func updateLiveActivity(progress: Double, message: String) {
    Task {
        for activity in Activity<ReadytoReachAttributes>.activities {
            await activity.update(using: .init(progress: progress, message: message))
        }
    }
}

// 结束实时活动
func endLiveActivity() {
    Task {
        for activity in Activity<ReadytoReachAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
    }
}

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        if let error = error {
            print("通知权限请求失败: \(error)")
        } else {
            print("通知权限请求结果: \(granted)")
        }
    }
}
