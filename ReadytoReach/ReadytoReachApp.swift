//
//  ReadytoReachApp.swift
//  ReadytoReach
//
//  Created by Less is more on 11/07/2025.
//

import SwiftUI

@main
struct ReadytoReachApp: App {
    @StateObject private var appDelegate = AppDelegate()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate)
                .onOpenURL { url in
                    appDelegate.handleURL(url)
                }
        }
    }
}

class AppDelegate: ObservableObject {
    func handleURL(_ url: URL) {
        guard url.scheme == "readytoreach" else { return }
        
        if url.host == "open" {
            // 解析logo参数
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let logoItem = queryItems.first(where: { $0.name == "logo" }),
               let logo = logoItem.value {
                // 在主线程执行
                DispatchQueue.main.async {
                    self.openSearchItem(logo: logo)
                }
            }
        }
    }
    
    private func openSearchItem(logo: String) {
        let appGroupID = "group.com.zisa.ReadytoReach"
        guard let groupDefaults = UserDefaults(suiteName: appGroupID) else { return }
        
        // 从App Group读取搜索项设置
        var searchItemSettings: [UnifiedSearchItem] = []
        if let data = groupDefaults.data(forKey: "SearchItemSettingsKey"),
           let decoded = try? JSONDecoder().decode([UnifiedSearchItem].self, from: data) {
            searchItemSettings = decoded
        }
        
        // 如果App Group中没有，尝试从标准UserDefaults读取
        if searchItemSettings.isEmpty {
            if let data = UserDefaults.standard.data(forKey: "SearchItemSettingsKey"),
               let decoded = try? JSONDecoder().decode([UnifiedSearchItem].self, from: data) {
                searchItemSettings = decoded
            }
        }
        
        // 查找对应的搜索项
        guard let item = searchItemSettings.first(where: { $0.logo == logo }) else { return }
        
        // 获取搜索模式（从App Group读取，默认为app）
        let modeKey = "ItemMode_\(logo)"
        let modeString = groupDefaults.string(forKey: modeKey) ?? "app"
        let mode = modeString == "web" ? "web" : "app"
        
        // 获取默认浏览器设置
        let defaultBrowserKey = "DefaultWebBrowserKey"
        let browserString = groupDefaults.string(forKey: defaultBrowserKey) ?? UserDefaults.standard.string(forKey: defaultBrowserKey) ?? "chrome"
        let schemePrefix = browserString == "safari" ? "https://" : "googlechrome://"
        
        // 构建URL并打开（没有query，直接打开APP主界面）
        var targetURL: URL?
        
        if mode == "app", let scheme = item.appUrlScheme {
            // App模式：优先使用appUrlScheme
            var urlString = scheme
            // 移除{query}占位符，或者使用基础scheme打开
            if let baseScheme = scheme.components(separatedBy: "?").first {
                urlString = baseScheme
            } else {
                urlString = scheme.replacingOccurrences(of: "{query}", with: "")
            }
            targetURL = URL(string: urlString)
            // 如果appUrlScheme无效，回退到webUrl
            if targetURL == nil, let webUrl = item.webUrl {
                let urlString = schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: "")
                targetURL = URL(string: urlString)
            }
        } else if let webUrl = item.webUrl {
            // Web模式：使用webUrl
            let urlString = schemePrefix + webUrl.replacingOccurrences(of: "{query}", with: "")
            targetURL = URL(string: urlString)
            // 如果webUrl无效，回退到appUrlScheme
            if targetURL == nil, let scheme = item.appUrlScheme {
                var appUrlString = scheme
                if let baseScheme = scheme.components(separatedBy: "?").first {
                    appUrlString = baseScheme
                } else {
                    appUrlString = scheme.replacingOccurrences(of: "{query}", with: "")
                }
                targetURL = URL(string: appUrlString)
            }
        }
        
        // 打开URL
        if let url = targetURL {
            UIApplication.shared.open(url)
        }
    }
}

// 搜索项数据结构（与主App保持一致）
struct UnifiedSearchItem: Codable, Identifiable {
    let id: UUID
    let name: String
    let logo: String
    let appUrlScheme: String?
    let webUrl: String?
    var isHidden: Bool
    var appKeyword: String?
    var webKeyword: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, logo, appUrlScheme, webUrl, isHidden, appKeyword, webKeyword
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        logo = try container.decode(String.self, forKey: .logo)
        appUrlScheme = try container.decodeIfPresent(String.self, forKey: .appUrlScheme)
        webUrl = try container.decodeIfPresent(String.self, forKey: .webUrl)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        appKeyword = try container.decodeIfPresent(String.self, forKey: .appKeyword)
        webKeyword = try container.decodeIfPresent(String.self, forKey: .webKeyword)
    }
}
