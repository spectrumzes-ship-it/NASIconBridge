// Copyright (c) 2026 SPARKY. Created by Kevin.
// Personal household use only; commercial use prohibited. See LICENSE.
import Foundation

// Translate presentation strings only. Paths and the engine's stable status keys
// remain unchanged, so language selection cannot affect matching or recovery.
final class Localization {
    static let shared = Localization()
    var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: "interfaceLanguage")
            NotificationCenter.default.post(name: .interfaceLanguageChanged, object: nil)
        }
    }
    struct Entry: Decodable { let zh: String; let en: String }
    struct Rule { let entry: Entry; let regex: NSRegularExpression; let indices: [Int] }
    private let exact: [String: String]
    private let rules: [Rule]
    private init() {
        language = UserDefaults.standard.string(forKey: "interfaceLanguage") == "en" ? "en" : "zh-Hant"
        let entries: [Entry] = Bundle.main.url(forResource: "Translations", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        var table: [String: String] = [:]; var compiled: [Rule] = []
        let token = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        for entry in entries {
            let range = NSRange(entry.zh.startIndex..., in: entry.zh)
            let matches = token.matches(in: entry.zh, range: range)
            if matches.isEmpty { table[entry.zh] = entry.en; continue }
            let source = entry.zh as NSString
            var pattern = "^"; var cursor = 0; var indices: [Int] = []
            for match in matches {
                pattern += NSRegularExpression.escapedPattern(for: source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
                pattern += "([\\s\\S]*?)"
                indices.append(Int(source.substring(with: match.range(at: 1)))!)
                cursor = NSMaxRange(match.range)
            }
            pattern += NSRegularExpression.escapedPattern(for: source.substring(from: cursor)) + "$"
            if let regex = try? NSRegularExpression(pattern: pattern) { compiled.append(Rule(entry: entry, regex: regex, indices: indices)) }
        }
        exact = table
        rules = compiled.sorted { $0.entry.zh.count > $1.entry.zh.count }
    }
    func translate(_ text: String, depth: Int = 0) -> String {
        guard language == "en", depth < 5 else { return text }
        if let translated = exact[text] { return translated }
        for rule in rules {
            guard let match = rule.regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let source = text as NSString
            var values: [Int: String] = [:]
            for (position, index) in rule.indices.enumerated() {
                var value = source.substring(with: match.range(at: position + 1))
                let nestedErrors = ["上次結果已從畫面清除，但紀錄檔未能清除：{0}", "無法列出子目錄：{0}", "目標未通過 metadata 測試：{0}。請檢查 NAS 的 macOS／SMB metadata 支援設定。", "{0}。仍可原樣複製來源 resource fork；需要原生重建的項目將列為失敗。"]
                if value.hasPrefix("；失敗 ") || nestedErrors.contains(rule.entry.zh) || (rule.entry.zh == "{0}；回復失敗：{1}；備份：{2}" && index < 2) {
                    value = translate(value, depth: depth + 1)
                }
                values[index] = value
            }
            // Replace placeholders in a single pass; captured folder names
            // containing {0} or similar text must never be reinterpreted.
            let token = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
            let target = rule.entry.en as NSString
            var result = ""; var cursor = 0
            for placeholder in token.matches(in: rule.entry.en, range: NSRange(location: 0, length: target.length)) {
                result += target.substring(with: NSRange(location: cursor, length: placeholder.range.location - cursor))
                let index = Int(target.substring(with: placeholder.range(at: 1)))!
                result += values[index] ?? ""
                cursor = NSMaxRange(placeholder.range)
            }
            return result + target.substring(from: cursor)
        }
        // POSIX errors are composed from an action followed by its OS message.
        if let separator = text.range(of: "：") {
            let prefix = String(text[..<separator.lowerBound])
            let translated = translate(prefix, depth: depth + 1)
            if translated != prefix { return translated + ": " + text[separator.upperBound...] }
        }
        return text
    }
}
func tr(_ text: String) -> String { Localization.shared.translate(text) }
extension Notification.Name { static let interfaceLanguageChanged = Notification.Name("NASIconBridge.interfaceLanguageChanged") }
