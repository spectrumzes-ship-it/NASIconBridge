// Copyright (c) 2026 SPARKY. Created by Kevin.
// Personal household use only; commercial use prohibited. See LICENSE.
import Foundation
import AppKit
import Darwin

struct BridgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
let finderKey = "com.apple.FinderInfo"
let resourceKey = "com.apple.ResourceFork"
let carrierName = "Icon\r"
let fm = FileManager.default

func systemError(_ action: String) -> BridgeError { BridgeError("\(action)：\(String(cString: strerror(errno)))") }
func attribute(_ url: URL, _ name: String) throws -> Data? {
    for attempt in 0..<3 {
        let size = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 {
            if errno == ENOATTR { return nil }
            throw systemError("讀取 \(name)")
        }
        guard size <= 64 * 1024 * 1024 else { throw BridgeError("metadata 超過 64 MB，已略過") }
        // Some SMB servers report a size for an absent ResourceFork, then
        // ENOATTR on the actual read. An absent value is still nil; callers
        // checking a just-written value must independently compare it.
        // Keep a nonempty buffer so size zero cannot become another size query.
        var data = Data(count: max(1, size))
        let capacity = data.count
        let count = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, capacity, 0, XATTR_NOFOLLOW) }
        if count < 0 {
            if errno == ENOATTR { return nil }
            if errno == ERANGE && attempt < 2 { continue }
            throw systemError("讀取 \(name)（預期 \(size) bytes）")
        }
        if count != size {
            if attempt < 2 { continue }
            throw BridgeError("\(name) 長度持續變動：預期 \(size)，實際 \(count) bytes")
        }
        return Data(data.prefix(count))
    }
    throw BridgeError("metadata 讀取重試失敗")
}
func putAttribute(_ url: URL, _ name: String, _ data: Data?) throws {
    if let data = data {
        // SMB may report successful removexattr while keeping the old fork
        // length. Open the existing named fork without O_TRUNC (unsupported
        // by some NAS servers), then explicitly truncate before replacement.
        if name == resourceKey, let old = try attribute(url, name), old.count > data.count {
            let forkPath = url.path + "/..namedfork/rsrc"
            let fd = open(forkPath, O_WRONLY)
            guard fd >= 0 else { throw systemError("開啟舊 resource fork") }
            defer { close(fd) }
            guard ftruncate(fd, 0) == 0 else { throw systemError("截短舊 resource fork") }
        }
        let rc = data.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
        guard rc == 0 else { throw systemError("寫入 \(name)") }
    } else {
        if removexattr(url.path, name, XATTR_NOFOLLOW) != 0 && errno != ENOATTR { throw systemError("移除 \(name)") }
    }
}
func attributeNames(_ url: URL) throws -> [String] {
    let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
    guard size >= 0 else { throw systemError("列出 metadata") }
    guard size <= 1024 * 1024 else { throw BridgeError("metadata 名稱清單過大") }
    var bytes = [CChar](repeating: 0, count: size)
    let n = listxattr(url.path, &bytes, size, XATTR_NOFOLLOW)
    guard n == size else { throw systemError("metadata 清單已變動") }
    return Data(bytes.map { UInt8(bitPattern: $0) }).split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
}
func allAttributes(_ url: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for key in try attributeNames(url) {
        if let value = try attribute(url, key) { result[key] = value }
    }
    return result
}
func directoryResource(_ folder: URL, names: [String], reader: (URL, String) throws -> Data? = attribute) throws -> Data? {
    // AFP returns EPERM for a resource fork requested on a directory even when
    // its Icon CR carrier is readable. SMB can return an unlisted empty fork.
    // Only read a directory fork if listxattr actually advertises one; real
    // carrier forks remain mandatory, strict reads through allAttributes.
    guard names.contains(resourceKey) else { return nil }
    return try reader(folder, resourceKey)
}
func hasCustom(_ data: Data?) -> Bool { guard let d = data, d.count == 32 else { return false }; return d[8] & 0x04 != 0 }
func withCustomFlag(_ data: Data?) throws -> Data {
    guard data == nil || data!.count == 32 else { throw BridgeError("FinderInfo 長度異常") }
    var value = data ?? Data(count: 32)
    value[8] |= 0x04
    return value
}
func fileSystem(_ url: URL) -> String {
    var info = statfs()
    guard statfs(url.path, &info) == 0 else { return "未知" }
    return withUnsafePointer(to: &info.f_fstypename) { $0.withMemoryRebound(to: CChar.self, capacity: 16) { String(cString: $0) } }
}
enum ConnectionRole: String {
    case afp = "AFP", smb = "SMB"
    var filesystem: String { self == .afp ? "afpfs" : "smbfs" }
}
func protocolName(_ filesystem: String) -> String {
    switch filesystem { case "afpfs": return "AFP"; case "smbfs": return "SMB"; case "apfs", "hfs": return "本機磁碟（\(filesystem)）"; default: return filesystem }
}
func droppedURL(_ item: Any) -> URL? {
    if let url = item as? URL { return url.isFileURL ? url : nil }
    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { return url }
    if let text = item as? String, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.isFileURL { return url }
    return nil
}
func selectedDirectory(_ input: URL) throws -> URL {
    guard input.isFileURL else { throw BridgeError("請拖入 Finder 的已掛載資料夾，不接受網路網址") }
    var url = (input as NSURL).filePathURL ?? input
    let values = try url.resourceValues(forKeys: [.isAliasFileKey])
    if values.isAliasFile == true { url = try URL(resolvingAliasFileAt: url, options: [.withoutUI, .withoutMounting]) }
    url = url.standardizedFileURL.resolvingSymlinksInPath()
    return try checked(url, "")
}
func selectedNetworkDirectory(_ input: URL, role: ConnectionRole) throws -> URL {
    let url = try selectedDirectory(input)
    let filesystem = fileSystem(url)
    guard filesystem == role.filesystem else { throw BridgeError("此目錄使用 \(protocolName(filesystem))：\(url.path)\n這個區域需要 \(role.rawValue)。請改拖另一個掛載，或從「已掛載的 \(role.rawValue)」選取。") }
    return url
}
struct MountedDirectory: Identifiable {
    var url: URL
    var filesystem: String
    var id: String { url.path }
}
func mountedNetworkDirectories() -> [MountedDirectory] {
    let root = URL(fileURLWithPath: "/Volumes", isDirectory: true)
    return ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
        let filesystem = fileSystem(url)
        guard filesystem == "afpfs" || filesystem == "smbfs" else { return nil }
        return MountedDirectory(url: url, filesystem: filesystem)
    }.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
}
func backupName() -> String {
    "NASIconBridge-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + String(UUID().uuidString.prefix(8))
}
func checked(_ root: URL, _ relative: String, directory: Bool = true) throws -> URL {
    guard relative.isEmpty || (!relative.hasPrefix("/") && relative.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw BridgeError("不安全的相對路徑") }
    let base = root.standardizedFileURL
    var node = base
    for component in [String](arrayLiteral: "") + relative.split(separator: "/").map(String.init) {
        if !component.isEmpty { node.appendPathComponent(component) }
        let values = try node.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else { throw BridgeError("略過符號連結：\(node.lastPathComponent)") }
        guard values.isDirectory == true else { throw BridgeError("目錄不存在或類型不符") }
    }
    guard node.resolvingSymlinksInPath().path == node.standardizedFileURL.path else { throw BridgeError("路徑包含符號連結") }
    return node
}
struct CarrierState: Codable, Equatable {
    var data: Data
    var attributes: [String: Data]
    var permissions: Int
}
struct IconState: Codable, Equatable {
    var finder: Data?
    var resource: Data?
    var carrier: CarrierState?
}
func readState(_ folder: URL) throws -> IconState {
    let url = folder.appendingPathComponent(carrierName)
    var carrier: CarrierState? = nil
    if fm.fileExists(atPath: url.path) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isSymbolicLink != true && values.isRegularFile == true else { throw BridgeError("Icon\\r 不是一般檔案，拒絕操作") }
        guard (values.fileSize ?? 0) <= 64 * 1024 * 1024 else { throw BridgeError("Icon\\r 大於 64 MB") }
        let fileAttributes = try fm.attributesOfItem(atPath: url.path)
        guard (fileAttributes[.referenceCount] as? NSNumber)?.intValue == 1 else { throw BridgeError("Icon\\r 有硬連結，拒絕操作") }
        let mode = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        carrier = CarrierState(data: try Data(contentsOf: url), attributes: try allAttributes(url), permissions: mode)
    }
    return IconState(finder: try attribute(folder, finderKey), resource: try directoryResource(folder, names: attributeNames(folder)), carrier: carrier)
}
func restoreState(_ state: IconState, to folder: URL) throws {
    let currentState = try readState(folder) // Reject unsafe carriers before writing anything.
    let url = folder.appendingPathComponent(carrierName)
    if let carrier = state.carrier {
        if !fm.fileExists(atPath: url.path) { guard fm.createFile(atPath: url.path, contents: nil) else { throw BridgeError("無法建立 Icon\\r") } }
        if currentState.carrier?.data != carrier.data { try carrier.data.write(to: url) } // Keep the existing inode and its permissions/ACLs.
        let current = try allAttributes(url)
        for key in current.keys where carrier.attributes[key] == nil { try putAttribute(url, key, nil) }
        for (key, value) in carrier.attributes where current[key] != value { try putAttribute(url, key, value) }
        if currentState.carrier?.permissions != carrier.permissions { try fm.setAttributes([.posixPermissions: carrier.permissions], ofItemAtPath: url.path) }
    } else if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    if currentState.resource != state.resource { try putAttribute(folder, resourceKey, state.resource) }
    if currentState.finder != state.finder { try putAttribute(folder, finderKey, state.finder) }
    guard try readState(folder) == state else { throw BridgeError("還原後讀回結果不一致") }
    onMain { NSWorkspace.shared.noteFileSystemChanged(folder.path) }
}
struct Candidate: Codable {
    var relative: String
    var source: IconState
    var imageTIFF: Data?
    var destination: IconState
}
struct Entry: Codable {
    var relative: String
    var original: IconState
    var source: IconState
    var imageTIFF: Data?
    var expected: IconState?
    var phase: String
}
struct Manifest: Codable {
    var version = 1
    var destinationRoot: String
    var sourceRoot: String
    var created = Date()
    var entries: [Entry] = []
    var entryCount: Int?
}
struct ReportRow: Codable { var path: String; var status: String; var detail: String }
struct WorkProgress: Codable, Equatable {
    var stage: String
    var completed: Int
    var total: Int?
    var detail: String
    var fraction: Double? {
        guard let total = total, total > 0 else { return nil }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}
enum OperationKind: String, Codable { case preview, apply, probe, restorePreview, restore }
struct SavedRun: Codable {
    var started = Date()
    var finished: Date?
    var kind: OperationKind
    var state: String
    var summary: String
    var source: String?
    var target: String?
    var backup: String?
    var rows: [ReportRow]
}
func resultSummary(kind: OperationKind, rows: [ReportRow], failure: String?) -> (state: String, message: String) {
    let errors = rows.filter { $0.status.contains("失敗") || $0.status.contains("手動") }.count
    let skipped = rows.filter { $0.status == "略過" }.count
    if let failure = failure { return (failure.contains("已停止") ? "stopped" : "failed", failure) }
    let suffix = errors > 0 ? "；失敗 \(errors) 項，請查看清單" : ""
    let state = errors > 0 ? "partial" : "complete"
    switch kind {
    case .preview:
        let count = rows.filter { $0.status == "可套用" }.count
        return (state, "預覽完成：找到 \(count) 個可套用圖示；略過 \(skipped) 項\(suffix)。尚未寫入 NAS。")
    case .apply:
        let count = rows.filter { $0.status == "成功" }.count
        if count == 0 && errors == 0 { return (state, "掃描完成，沒有可套用的圖示；未修改 NAS。") }
        return (state, "\(errors > 0 ? "部分完成" : "套用完成")：成功 \(count) 項\(suffix)。Finder 顯示仍需確認。")
    case .probe: return (state, "SMB 支援檢測完成\(suffix)。既有資料夾圖示未套用。")
    case .restorePreview:
        return (state, "還原預覽完成：\(rows.filter { $0.status == "可還原" }.count) 項可還原\(suffix)。尚未寫入 NAS。")
    case .restore:
        return (state, "\(errors > 0 ? "部分還原" : "還原完成")：已還原 \(rows.filter { $0.status == "已還原" }.count) 項\(suffix)。")
    }
}
final class StopToken: @unchecked Sendable {
    private let lock = NSLock(); private var stopped = false
    func stop() { lock.lock(); stopped = true; lock.unlock() }
    func check() throws { lock.lock(); let value = stopped; lock.unlock(); if value { throw BridgeError("已停止；已完成項目保留，可用備份還原") } }
}
func onMain<T>(_ body: @escaping () -> T) -> T { if Thread.isMainThread { return body() }; return DispatchQueue.main.sync(execute: body) }

final class Engine: @unchecked Sendable {
    let emit: (ReportRow) -> Void
    let stop: StopToken
    let updateProgress: (WorkProgress) -> Void
    init(stop: StopToken, progress: @escaping (WorkProgress) -> Void = { _ in }, emit: @escaping (ReportRow) -> Void) {
        self.stop = stop; self.emit = emit; self.updateProgress = progress
    }
    func progress(_ stage: String, _ completed: Int = 0, _ total: Int? = nil, _ detail: String = "") {
        updateProgress(WorkProgress(stage: stage, completed: completed, total: total, detail: detail))
    }
    func scan(source: URL, destination: URL) throws -> [Candidate] {
        _ = try checked(source, ""); _ = try checked(destination, "")
        guard source.standardizedFileURL.path != destination.standardizedFileURL.path else { throw BridgeError("來源與目標不可選擇同一路徑") }
        progress("掃描資料夾", 0, nil, "正在搜尋；總數尚未知，未寫入 NAS")
        var queue = [""]; var candidates: [Candidate] = []; var count = 0
        while let relative = queue.popLast() {
            try stop.check()
            let folder: URL
            do { folder = try checked(source, relative) } catch { emit(ReportRow(path: relative, status: "略過", detail: error.localizedDescription)); continue }
            count += 1
            if count == 1 || count % 10 == 0 { progress("掃描資料夾", count, nil, "已掃描 \(count) 個；已找到 \(candidates.count) 個圖示") }
            if count % 250 == 0 { emit(ReportRow(path: relative, status: "掃描中", detail: "已掃描 \(count) 個資料夾")) }
            do {
                let state = try readState(folder)
                let fork = state.carrier?.attributes[resourceKey]
                if hasCustom(state.finder) || (fork?.isEmpty == false) {
                    let target = try checked(destination, relative)
                    let targetState = try readState(target)
                    let image: Data? = (hasCustom(state.finder) && fork?.isEmpty != false) ? onMain { let i = NSWorkspace.shared.icon(forFile: folder.path); i.size = NSSize(width: 512, height: 512); return i.tiffRepresentation } : nil
                    candidates.append(Candidate(relative: relative, source: state, imageTIFF: image, destination: targetState))
                    emit(ReportRow(path: relative.isEmpty ? "（根目錄）" : relative, status: "可套用", detail: "FinderInfo：\(hasCustom(state.finder) ? "自訂圖示" : "無旗標")；Icon\\r resource fork：\(fork?.count ?? 0) bytes；資料夾 fork：\(state.resource?.count ?? 0) bytes"))
                }
            } catch { emit(ReportRow(path: relative, status: "掃描失敗", detail: error.localizedDescription)) }
            do {
                let children = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [])
                for child in children.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                    if values.isSymbolicLink == true { emit(ReportRow(path: relative + "/" + child.lastPathComponent, status: "略過", detail: "符號連結")); continue }
                    if values.isDirectory == true && values.isPackage != true && !child.lastPathComponent.hasPrefix(".NASIconBridge-Probe-") {
                        queue.append(relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                    }
                }
            } catch { emit(ReportRow(path: relative, status: "掃描失敗", detail: "無法列出子目錄：\(error.localizedDescription)")) }
        }
        progress("掃描完成", count, count, "找到 \(candidates.count) 個對應圖示")
        emit(ReportRow(path: "", status: "掃描完成", detail: "掃描 \(count) 個資料夾，找到 \(candidates.count) 個對應圖示。此操作未寫入 NAS。"))
        return candidates
    }
    func process(source: URL, destination: URL, dryRun: Bool, backup: URL?) throws -> [Candidate] {
        let items = try scan(source: source, destination: destination)
        if dryRun || items.isEmpty { return items }
        try stop.check()
        guard let backup = backup else { throw BridgeError("正式處理必須有本機備份位置") }
        try apply(items, source: source, destination: destination, backup: backup)
        return items
    }
    @discardableResult
    func probe(_ destination: URL) throws -> Bool {
        progress("檢測 SMB 支援", 0, nil, "正在獨立暫存資料夾測試 metadata")
        let root = try checked(destination, "")
        let probe = root.appendingPathComponent(".NASIconBridge-Probe-" + UUID().uuidString)
        try fm.createDirectory(at: probe, withIntermediateDirectories: false)
        var errorFound: Error?
        var nativeSupported = false
        var nativeFailure = ""
        do {
            var info = Data(count: 32); info[8] = 0x04
            try putAttribute(probe, finderKey, info)
            guard try attribute(probe, finderKey) == info else { throw BridgeError("伺服器未保留 FinderInfo") }
            let carrier = probe.appendingPathComponent(carrierName)
            guard fm.createFile(atPath: carrier.path, contents: Data()) else { throw BridgeError("無法建立 Icon\\r") }
            let fork = Data("NASIconBridge-resource-test".utf8)
            try putAttribute(carrier, resourceKey, fork)
            guard try attribute(carrier, resourceKey) == fork else { throw BridgeError("伺服器未保留 resource fork") }
            let shorter = Data("short".utf8)
            try putAttribute(carrier, resourceKey, shorter)
            guard try attribute(carrier, resourceKey) == shorter else { throw BridgeError("替換較小 resource fork 時出現殘留資料") }
            try fm.removeItem(at: carrier)
            do {
                let success = onMain { NSWorkspace.shared.setIcon(NSImage(named: NSImage.folderName), forFile: probe.path, options: []) }
                guard success else { throw BridgeError("macOS 原生圖示重建失敗") }
                let state = try readState(probe)
                guard hasCustom(state.finder), state.carrier?.attributes[resourceKey]?.isEmpty == false else { throw BridgeError("原生圖示 metadata 讀回驗證失敗") }
                nativeSupported = true
            } catch { nativeFailure = error.localizedDescription }
        } catch { errorFound = error }
        do { try fm.removeItem(at: probe) } catch { throw BridgeError("測試資料夾未能刪除：\(probe.path)。\(error.localizedDescription)") }
        if let error = errorFound { throw BridgeError("目標未通過 metadata 測試：\(error.localizedDescription)。請檢查 NAS 的 macOS／SMB metadata 支援設定。") }
        progress("SMB 檢測通過", 1, 1)
        emit(ReportRow(path: "", status: "檢測通過", detail: "FinderInfo、Icon\\r 與 resource fork 可寫入及讀回。尚未驗證重新掛載後的持久性或 Finder 快取。"))
        if !nativeSupported { emit(ReportRow(path: "", status: "提示", detail: "\(nativeFailure)。仍可原樣複製來源 resource fork；需要原生重建的項目將列為失敗。")) }
        return nativeSupported
    }
    func save(_ manifest: Manifest, at bundle: URL, changedIndex: Int? = nil, showProgress: Bool = false) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let indices = changedIndex.map { [$0] } ?? Array(manifest.entries.indices)
        if showProgress { progress("保存本機備份", 0, indices.count) }
        for (position, index) in indices.enumerated() {
            try encoder.encode(manifest.entries[index]).write(to: bundle.appendingPathComponent("entry-\(index).json"), options: .atomic)
            if showProgress { progress("保存本機備份", position + 1, indices.count) }
        }
        var header = manifest; header.entryCount = manifest.entries.count; header.entries = []
        try encoder.encode(header).write(to: bundle.appendingPathComponent("manifest.json"), options: .atomic)
    }
    func load(_ bundle: URL) throws -> Manifest {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var manifest = try decoder.decode(Manifest.self, from: Data(contentsOf: bundle.appendingPathComponent("manifest.json")))
        guard manifest.version == 1, let count = manifest.entryCount, count >= 0, count <= 100_000 else { throw BridgeError("不支援或無效的備份版本／項目數") }
        manifest.entries = []
        for index in 0..<count {
            let url = bundle.appendingPathComponent("entry-\(index).json")
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 256 * 1024 * 1024 else { throw BridgeError("備份項目不是一般檔案或過大") }
            manifest.entries.append(try decoder.decode(Entry.self, from: Data(contentsOf: url)))
        }
        guard Set(manifest.entries.map { $0.relative }).count == count else { throw BridgeError("備份含重複路徑") }
        return manifest
    }
    func apply(_ candidates: [Candidate], source: URL, destination: URL, backup: URL) throws {
        guard !candidates.isEmpty else { throw BridgeError("請先掃描，找到可套用的圖示") }
        _ = try checked(source, ""); _ = try checked(destination, "")
        let backupPath = backup.resolvingSymlinksInPath().path
        for root in [source, destination] { guard backupPath != root.path && !backupPath.hasPrefix(root.path + "/") else { throw BridgeError("備份必須存於 AFP／SMB 根目錄以外") } }
        guard fileSystem(backup.deletingLastPathComponent()) == "apfs" || fileSystem(backup.deletingLastPathComponent()) == "hfs" else { throw BridgeError("請把備份存至本機 APFS／HFS+ 磁碟") }
        let nativeSupported = try probe(destination)
        try fm.createDirectory(at: backup, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var manifest = Manifest(destinationRoot: destination.standardizedFileURL.path, sourceRoot: source.standardizedFileURL.path)
        // Save every source snapshot before any write: AFP and SMB may expose the same server inode.
        progress("核對及準備備份", 0, candidates.count)
        for (position, item) in candidates.enumerated() {
            try stop.check()
            let target = try checked(destination, item.relative)
            let original = try readState(target)
            let sourceFolder = try checked(source, item.relative)
            guard try readState(sourceFolder) == item.source else { throw BridgeError("來源已於掃描後變動：\(item.relative)。請重新掃描") }
            guard original == item.destination else { throw BridgeError("目標已於掃描後變動：\(item.relative)。請重新掃描") }
            manifest.entries.append(Entry(relative: item.relative, original: original, source: item.source, imageTIFF: item.imageTIFF, expected: nil, phase: "prepared"))
            progress("核對及準備備份", position + 1, candidates.count)
        }
        try save(manifest, at: backup, showProgress: true)
        emit(ReportRow(path: backup.path, status: "備份完成", detail: "已保存所有來源圖示快照及目標原始 metadata"))
        progress("套用及驗證圖示", 0, manifest.entries.count)
        for index in manifest.entries.indices {
            try stop.check()
            defer { progress("套用及驗證圖示", index + 1, manifest.entries.count) }
            let entry = manifest.entries[index]
            let target: URL
            do { target = try checked(destination, entry.relative) } catch { emit(ReportRow(path: entry.relative, status: "失敗", detail: error.localizedDescription)); continue }
            do {
                guard entry.source.carrier?.attributes[resourceKey]?.isEmpty == false || nativeSupported else { throw BridgeError("來源缺少可用的原始 resource fork，而此 SMB 未通過 macOS 原生圖示重建測試；未修改此資料夾") }
                guard try readState(target) == entry.original else { throw BridgeError("目標已變動，已略過") }
                if entry.original.carrier?.data.isEmpty == false { throw BridgeError("目標 Icon\\r 含有資料，避免覆蓋而略過") }
                manifest.entries[index].phase = "writing"; try save(manifest, at: backup, changedIndex: index)
            } catch { emit(ReportRow(path: entry.relative, status: "失敗", detail: error.localizedDescription)); continue }
            do {
                let rawTransfer = entry.source.carrier?.attributes[resourceKey]?.isEmpty == false
                if let carrier = entry.source.carrier, let resource = carrier.attributes[resourceKey], !resource.isEmpty {
                    let icon = target.appendingPathComponent(carrierName)
                    if !fm.fileExists(atPath: icon.path) { guard fm.createFile(atPath: icon.path, contents: Data()) else { throw BridgeError("無法建立 Icon\\r") } }
                    try carrier.data.write(to: icon)
                    try putAttribute(icon, resourceKey, resource)
                    var fi = carrier.attributes[finderKey] ?? Data(count: 32)
                    guard fi.count == 32 else { throw BridgeError("來源 Icon\\r FinderInfo 長度異常") }
                    fi[8] |= 0x40 // Keep the carrier invisible in Finder.
                    try putAttribute(icon, finderKey, fi)
                    try putAttribute(target, finderKey, withCustomFlag(entry.original.finder))
                    guard try attribute(icon, resourceKey) == resource else { throw BridgeError("resource fork 讀回不一致") }
                } else {
                    guard let bytes = entry.imageTIFF, let image = NSImage(data: bytes) else { throw BridgeError("來源缺少可用的圖示 resource fork／影像") }
                    let success = onMain { NSWorkspace.shared.setIcon(image, forFile: target.path, options: []) }
                    guard success else { throw BridgeError("macOS 原生重新套用失敗") }
                    try putAttribute(target, finderKey, withCustomFlag(entry.original.finder))
                }
                let actual = try readState(target)
                guard actual.finder == (try withCustomFlag(entry.original.finder)), actual.resource == entry.original.resource, actual.carrier?.attributes[resourceKey]?.isEmpty == false else { throw BridgeError("圖示 metadata 讀回驗證失敗") }
                manifest.entries[index].expected = actual; manifest.entries[index].phase = "applied"
                try save(manifest, at: backup, changedIndex: index)
                onMain { NSWorkspace.shared.noteFileSystemChanged(target.path) }
                emit(ReportRow(path: entry.relative.isEmpty ? "（根目錄）" : entry.relative, status: "成功", detail: "\(rawTransfer ? "原樣複製 resource fork" : "原生影像備援（重新生成）")；已驗證 metadata；Finder 顯示請另行確認"))
            } catch {
                let failure = error.localizedDescription
                do {
                    let safeTarget = try checked(destination, entry.relative)
                    try restoreState(entry.original, to: safeTarget)
                    manifest.entries[index].phase = "rolledBack"; manifest.entries[index].expected = entry.original
                    try save(manifest, at: backup, changedIndex: index)
                    emit(ReportRow(path: entry.relative, status: "失敗／已回復", detail: failure))
                } catch {
                    emit(ReportRow(path: entry.relative, status: "需手動還原", detail: "\(failure)；回復失敗：\(error.localizedDescription)；備份：\(backup.path)"))
                    throw BridgeError("自動回復失敗，已停止後續寫入。請保留備份並檢查目標")
                }
            }
        }
    }
    func restore(backup: URL, destination: URL, dryRun: Bool, recoverInterrupted: Bool) throws {
        progress("讀取還原備份", 0, nil)
        var manifest = try load(backup)
        guard manifest.destinationRoot == destination.standardizedFileURL.path else { throw BridgeError("SMB 根目錄與備份記錄不一致，請選擇：\(manifest.destinationRoot)") }
        let restoreStage = dryRun ? "檢查可還原項目" : "還原並驗證圖示"
        progress(restoreStage, 0, manifest.entries.count)
        for index in manifest.entries.indices {
            try stop.check()
            defer { progress(restoreStage, index + 1, manifest.entries.count) }
            let entry = manifest.entries[index]
            if entry.phase == "prepared" || entry.phase == "rolledBack" || entry.phase == "restored" { continue }
            do {
                let target = try checked(destination, entry.relative)
                let actual = try readState(target)
                if let expected = entry.expected { guard actual == expected || actual == entry.original || (recoverInterrupted && entry.phase == "restoring") else { throw BridgeError("圖示已在套用後改動，拒絕覆蓋；請保留備份") } }
                else { guard recoverInterrupted && (entry.phase == "writing" || entry.phase == "restoring") else { throw BridgeError("上次寫入中斷，請勾選「復原中斷寫入」後再還原") } }
                if !dryRun {
                    manifest.entries[index].phase = "restoring"; try save(manifest, at: backup, changedIndex: index)
                    try restoreState(entry.original, to: target)
                    manifest.entries[index].phase = "restored"; try save(manifest, at: backup, changedIndex: index)
                }
                emit(ReportRow(path: entry.relative.isEmpty ? "（根目錄）" : entry.relative, status: dryRun ? "可還原" : "已還原", detail: "還原 SMB 原始圖示資料；一般檔案不受影響"))
            } catch { emit(ReportRow(path: entry.relative, status: "還原失敗", detail: error.localizedDescription)) }
        }
    }
}
