// Copyright (c) 2026 SPARKY. Created by Kevin.
// Personal household use only; commercial use prohibited. See LICENSE.
import SwiftUI
@preconcurrency import AppKit
import UniformTypeIdentifiers

@MainActor final class Model: ObservableObject {
    @Published var language = Localization.shared.language {
        didSet { Localization.shared.language = language }
    }
    @Published var showingAbout = false
    @Published var source: URL?
    @Published var target: URL?
    @Published var rows: [ReportRow] = []
    @Published var busy = false
    @Published var recoverInterrupted = false
    @Published var summary = "請選擇同一個 NAS 共享資料夾的 AFP 與 SMB 根目錄。"
    @Published var lastBackup: URL?
    @Published var afpHover = false
    @Published var smbHover = false
    @Published var progress: WorkProgress?
    @Published var resultState = "ready"
    @Published var lastFinished: Date?
    @Published var mounts: [MountedDirectory] = []
    var candidates: [Candidate] = []
    var token: StopToken?
    var started = Date()
    init() {
        // Remove legacy automatic logs. Paths/results now remain in memory only.
        let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NASIconBridge", isDirectory: true)
        do {
            for name in ["last-run.json", "selection.json"] {
                let file = directory.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
        } catch { summary = "上次結果已從畫面清除，但紀錄檔未能清除：\(error.localizedDescription)" }
    }
    func showBackup() {
        if let backup = lastBackup, fm.fileExists(atPath: backup.path) { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
        else if fm.fileExists(atPath: automaticBackupRoot.path) { NSWorkspace.shared.open(automaticBackupRoot) }
        else { alert("目前沒有找到正式套用的自動備份。Dry run 預覽不會建立備份。") }
    }
    func chooseFolder(_ title: String) -> URL? {
        let panel = NSOpenPanel(); panel.title = tr(title); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.message = tr("請選擇掛載路徑；也可按 ⌘⇧G 輸入 /Volumes/NAS 等完整路徑。")
        return panel.runModal() == .OK ? panel.url : nil
    }
    func refreshMounts() { mounts = mountedNetworkDirectories() }
    func selectSource() { if let url = chooseFolder("選擇 AFP 根目錄") { accept(url, role: .afp) } }
    func selectTarget() { if let url = chooseFolder("選擇 SMB 根目錄") { accept(url, role: .smb) } }
    func accept(_ input: URL, role: ConnectionRole) {
        guard !busy else { return }
        do {
            let url = try selectedNetworkDirectory(input, role: role)
            if role == .afp { source = url } else { target = url }
            invalidate()
            summary = "已確認 \(role.rawValue)：\(url.path)。兩側請選擇相同層級的資料夾。"
        } catch { alert(error.localizedDescription) }
    }
    func clear(_ role: ConnectionRole) { if role == .afp { source = nil } else { target = nil }; invalidate() }
    func receive(_ providers: [NSItemProvider], role: ConnectionRole) -> Bool {
        guard !busy, providers.count == 1, let provider = providers.first else {
            alert("每個區域請只拖入一個資料夾。子資料夾會自動遞迴處理。"); return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            let url = item.flatMap { droppedURL($0) }
            let failure = error?.localizedDescription
            DispatchQueue.main.async {
                guard !self.busy else { return }
                if let url = url { self.accept(url, role: role) }
                else { self.alert(failure ?? "無法取得資料夾路徑。請從 Finder 拖入，或使用已掛載目錄選單。") }
            }
        }
        return true
    }
    var automaticBackupRoot: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("backup", isDirectory: true)
    }
    func startProcessing(dryRun dry: Bool) {
        guard let source = source, let target = target else { return }
        do {
            _ = try selectedNetworkDirectory(source, role: .afp)
            _ = try selectedNetworkDirectory(target, role: .smb)
        } catch { alert(error.localizedDescription); return }
        let parent = automaticBackupRoot
        let backup = dry ? nil : parent.appendingPathComponent(backupName(), isDirectory: true)
        rows = []; candidates = []; lastBackup = nil
        run(dry ? "唯讀掃描中，未寫入 NAS……" : "掃描、檢測及備份套用中……", kind: dry ? .preview : .apply) { engine in
            defer {
                if let backup = backup, fm.fileExists(atPath: backup.appendingPathComponent("manifest.json").path) {
                    DispatchQueue.main.async { self.lastBackup = backup }
                }
            }
            if !dry {
                let filesystem = fileSystem(parent.deletingLastPathComponent())
                guard filesystem == "apfs" || filesystem == "hfs" else { throw BridgeError("請將 App 放在 Mac 本機磁碟；backup 必須保存在本機，不能放在 NAS") }
                do { try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
                catch { throw BridgeError("無法建立 App 同層的 backup 資料夾：\(parent.path)。請把 App 放到可寫入的本機資料夾。\(error.localizedDescription)") }
            }
            let items = try engine.process(source: source, destination: target, dryRun: dry, backup: backup)
            DispatchQueue.main.async {
                self.candidates = dry ? items : []
                if let backup = backup, fm.fileExists(atPath: backup.appendingPathComponent("manifest.json").path) { self.lastBackup = backup }
            }
        }
    }
    func invalidate() { candidates = []; rows = []; progress = nil; resultState = "ready"; lastFinished = nil; summary = "目錄已更改，請重新掃描。" }
    func alert(_ text: String) { let alert = NSAlert(); alert.messageText = "NAS Icon Bridge"; alert.informativeText = tr(text); alert.runModal() }
    func confirm(_ title: String, _ text: String) -> Bool {
        let a = NSAlert(); a.messageText = tr(title); a.informativeText = tr(text); a.alertStyle = .warning
        a.addButton(withTitle: tr("繼續")); a.addButton(withTitle: tr("取消")); return a.runModal() == .alertFirstButtonReturn
    }
    func run(_ title: String, kind: OperationKind, work: @escaping (Engine) throws -> Void) {
        busy = true; summary = title; resultState = "running"; started = Date(); lastFinished = nil
        progress = WorkProgress(stage: "開始處理", completed: 0, total: nil, detail: "")
        rows = []
        let firstRow = 0
        let stop = StopToken(); token = stop
        let engine = Engine(stop: stop, progress: { value in DispatchQueue.main.async { self.progress = value } }) {
            row in DispatchQueue.main.async { self.rows.append(row) }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let failure: String? = {
                do { try work(engine); return nil } catch { return error.localizedDescription }
            }()
            DispatchQueue.main.async {
                self.busy = false; self.token = nil; self.lastFinished = Date()
                let detail = failure.map { value in value.contains("已停止") && (kind == .preview || kind == .restorePreview) ? "唯讀掃描已停止，未寫入 NAS。" : value }
                if let detail = detail { self.rows.append(ReportRow(path: "", status: "已停止", detail: detail)) }
                let current = Array(self.rows.dropFirst(firstRow))
                let result = resultSummary(kind: kind, rows: current, failure: detail)
                self.resultState = result.state; self.summary = result.message
                if detail == nil {
                    self.progress = WorkProgress(stage: result.state == "partial" ? "處理結束，部分項目失敗" : (kind == .preview ? "預覽完成" : "處理完成"), completed: 1, total: 1, detail: "")
                } else if var p = self.progress { p.stage = result.state == "stopped" ? "已停止" : "發生錯誤"; p.total = nil; self.progress = p }
            }
        }
    }
    func scan() {
        guard let source = source, let target = target else { return }
        rows = []; candidates = []
        run("唯讀掃描中，未寫入 NAS……", kind: .preview) { engine in
            let items = try engine.scan(source: source, destination: target)
            DispatchQueue.main.async { self.candidates = items }
        }
    }
    func probe() {
        guard let target = target else { return }
        guard confirm("檢測目標 metadata 支援", "會在 SMB 根目錄建立一個隨機命名的暫存資料夾，測試後刪除。現有資料夾不會被套用圖示。") else { return }
        run("檢測 SMB 寫入支援……", kind: .probe) { try $0.probe(target) }
    }
    func apply() {
        guard let source = source, let target = target, !candidates.isEmpty else { alert("請先掃描並確認可套用項目。" ); return }
        guard let parent = chooseFolder("選擇本機備份位置；請勿選擇 NAS") else { return }
        let name = "NASIconBridge-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + String(UUID().uuidString.prefix(8))
        let backup = parent.appendingPathComponent(name)
        guard confirm("套用 \(candidates.count) 個資料夾圖示", "備份位置：\(backup.path)\n\n若 AFP 與 SMB 指向同一個 NAS 資料夾，metadata 修改也可能反映於 AFP。一般檔案不會被搬移或刪除。請暫停其他程式對這些資料夾的修改。") else { return }
        lastBackup = backup
        let items = candidates
        run("保存備份並套用圖示……", kind: .apply) { try $0.apply(items, source: source, destination: target, backup: backup) }
        candidates = []
    }
    func restore(dryRun dry: Bool = false) {
        guard let target = target else { return }
        guard let backup = chooseFolder("選擇包含 manifest.json 的 NASIconBridge 備份資料夾") else { return }
        let recover = recoverInterrupted
        if !dry && !confirm("還原 SMB 圖示", "將以備份中的原始資料還原圖示。若圖示在套用後另有更改，會略過；「復原中斷寫入」會允許還原未完成的項目。") { return }
        run(dry ? "唯讀檢查可還原項目……" : "還原圖示……", kind: dry ? .restorePreview : .restore) { try $0.restore(backup: backup, destination: target, dryRun: dry, recoverInterrupted: recover) }
        candidates = []
    }
    func export() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "NASIconBridge-report.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(rows.map { ReportRow(path: $0.path, status: tr($0.status), detail: tr($0.detail)) }).write(to: url, options: .atomic) } catch { alert(error.localizedDescription) }
    }
}
struct ContentView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("NAS Icon Bridge").font(.largeTitle.bold())
                Spacer()
                Picker(tr("語言"), selection: $model.language) {
                    Text("繁體中文").tag("zh-Hant")
                    Text("English").tag("en")
                }.pickerStyle(.segmented).frame(width: 250)
                Button(tr("關於")) { model.showingAbout = true }.controlSize(.large)
            }
            Text(tr("將 AFP 的 Finder 自訂資料夾圖示重新套用至 SMB")).font(.headline).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                FolderDropArea(model: model, role: .afp)
                FolderDropArea(model: model, role: .smb)
            }
            Text(tr("拖入共享根目錄或其中的資料夾均可；兩側必須是同一共享、同一層級。下層自訂圖示會自動遞迴處理。"))
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button { model.startProcessing(dryRun: true) } label: {
                    VStack(spacing: 6) {
                        Label(tr("測試掃描"), systemImage: "magnifyingglass").font(.system(size: 19, weight: .bold))
                        Text(tr("只預覽結果，不寫入 NAS")).font(.callout)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 78)
                        .background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(model.source == nil || model.target == nil)
                Button { model.startProcessing(dryRun: false) } label: {
                    VStack(spacing: 6) {
                        Label(tr("正式套用"), systemImage: "play.fill").font(.system(size: 19, weight: .bold))
                        Text(tr("自動備份，再寫入及驗證圖示")).font(.callout)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 78)
                        .background(Color.orange).clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(model.source == nil || model.target == nil)
            }.opacity(model.source == nil || model.target == nil ? 0.5 : 1)
            HStack(spacing: 12) {
                Button { model.showBackup() } label: { Label(tr("顯示備份"), systemImage: "folder.fill").font(.headline).padding(.horizontal, 10).padding(.vertical, 5) }
                Button { model.export() } label: { Label(tr("匯出結果"), systemImage: "square.and.arrow.up").font(.headline).padding(.horizontal, 10).padding(.vertical, 5) }.disabled(model.rows.isEmpty)
                Button { model.restore() } label: { Label(tr("從備份還原"), systemImage: "arrow.uturn.backward").font(.headline).padding(.horizontal, 10).padding(.vertical, 5) }.disabled(model.target == nil)
            }.buttonStyle(.bordered).controlSize(.large)
            Text(tr("正式套用會先檢測 SMB、保存本機備份，再寫入圖示。AFP 與 SMB 若指向同一份 NAS 資料，圖示變更也可能反映於 AFP；還原亦會影響同一份資料。"))
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup(tr("其他工具與還原")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(tr("檢測 SMB 支援")) { model.probe() }.disabled(model.target == nil)
                        Button(tr("手動選擇備份並套用")) { model.apply() }.disabled(model.candidates.isEmpty)
                    }
                    Button(tr("預覽可還原項目（不寫入）")) { model.restore(dryRun: true) }.disabled(model.target == nil)
                    Toggle(tr("復原中斷寫入"), isOn: $model.recoverInterrupted).toggleStyle(.checkbox)
                    Text(tr("自動備份：\(model.automaticBackupRoot.path)")).font(.caption).textSelection(.enabled)
                }.padding(.top, 8)
            }
            if let backup = model.lastBackup {
                Text(tr("最近備份：\(backup.path)")).font(.caption).textSelection(.enabled)
            }
            Divider()
            ProgressPanel(model: model)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(tr(row.status))  \(row.path)").font(.system(.body, design: .monospaced)).foregroundStyle(row.status.contains("失敗") || row.status.contains("手動") ? Color.red : Color.primary)
                            Text(tr(row.detail)).font(.caption).foregroundStyle(.secondary)
                        }.textSelection(.enabled)
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }.background(Color(nsColor: .textBackgroundColor)).border(Color.secondary.opacity(0.3))
            Text(tr("成功代表 metadata 寫入及讀回通過。Finder 快取與 NAS 重新掛載後的保留情況，仍須實際確認。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(minWidth: 980, minHeight: 780)
        .onAppear { model.refreshMounts() }
        .sheet(isPresented: $model.showingAbout) { AboutView() }
        .disabled(model.busy)
        .overlay(alignment: .bottomTrailing) { if model.busy { Button(tr("停止後續項目")) { model.token?.stop() }.buttonStyle(.borderedProminent).tint(.orange).controlSize(.large).padding(22) } }
    }
}
struct ProgressPanel: View {
    @ObservedObject var model: Model
    var color: Color {
        switch model.resultState { case "complete": return .green; case "partial", "stopped", "unknown": return .orange; case "failed": return .red; default: return .blue }
    }
    var heading: String {
        if model.busy { return model.progress?.stage ?? "正在處理" }
        switch model.resultState { case "complete": return "操作已結束"; case "partial": return "部分完成，請查看失敗項目"; case "stopped": return "已停止"; case "failed": return "未完成，發生錯誤"; case "unknown": return "上次完成狀態未知"; default: return "尚未開始" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: model.busy ? "arrow.triangle.2.circlepath" : (model.resultState == "complete" ? "checkmark.circle.fill" : "info.circle.fill")).foregroundStyle(color)
                Text(tr(heading)).font(.title3.bold())
                Spacer()
                if let p = model.progress, let fraction = p.fraction {
                    Text(tr("本階段 \(Int((fraction * 100).rounded()))％")).font(.title3.bold()).monospacedDigit()
                }
            }
            if let p = model.progress {
                if let fraction = p.fraction { ProgressView(value: fraction).progressViewStyle(.linear).tint(color) }
                else if model.busy { ProgressView().progressViewStyle(.linear).tint(color) }
                if model.busy {
                    Text(tr(p.total.map { "已處理 \(p.completed)／\($0) 項" } ?? (p.stage.contains("掃描") ? "已掃描 \(p.completed) 個資料夾；仍在搜尋，總數尚未知" : "正在處理，請稍候……")))
                        .font(.callout).monospacedDigit()
                    if !p.detail.isEmpty { Text(tr(p.detail)).font(.caption).foregroundStyle(.secondary) }
                }
            } else { ProgressView(value: 0).progressViewStyle(.linear).tint(color) }
            Text(tr(model.summary)).font(.body).textSelection(.enabled)
            if let date = model.lastFinished { Text(tr("結束時間：") + date.formatted(.dateTime.locale(Locale(identifier: model.language)))).font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4)))
    }
}
struct FolderDropArea: View {
    @ObservedObject var model: Model
    let role: ConnectionRole
    var accent: Color { role == .afp ? .blue : .teal }
    var hover: Bool { role == .afp ? model.afpHover : model.smbHover }
    var hoverBinding: Binding<Bool> { Binding(get: { hover }, set: { if role == .afp { model.afpHover = $0 } else { model.smbHover = $0 } }) }
    var url: URL? { role == .afp ? model.source : model.target }
    var options: [MountedDirectory] { model.mounts.filter { $0.filesystem == role.filesystem } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(role.rawValue).font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 7)
                    .background(accent, in: RoundedRectangle(cornerRadius: 9))
                Text(tr(role == .afp ? "AFP 來源（有圖示）" : "SMB 目標（套用圖示）")).font(.system(size: 18, weight: .bold))
                Spacer()
                if url != nil { Button(tr("清除")) { model.clear(role) }.font(.caption) }
            }
            if let url = url {
                Text(tr("已確認協定：\(protocolName(fileSystem(url)))")).font(.subheadline.bold()).foregroundStyle(Color.green)
                Text(url.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled).lineLimit(3)
            } else {
                Label(tr("將 Finder／桌面的資料夾拖到這裡"), systemImage: "arrow.down.to.line").font(.headline)
                Text(tr("只接受 \(role.rawValue) 掛載；會檢查協定")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(tr("選擇資料夾……")) { if role == .afp { model.selectSource() } else { model.selectTarget() } }
                Menu(tr("已掛載的 \(role.rawValue)")) {
                    if options.isEmpty { Text(tr("沒有找到此協定的掛載")) }
                    ForEach(options) { item in Button(item.url.path + "〔" + role.rawValue + "〕") { model.accept(item.url, role: role) } }
                    Divider()
                    Button(tr("重新整理掛載清單")) { model.refreshMounts() }
                }
            }.font(.headline).controlSize(.large).buttonStyle(.bordered)
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 14).fill(accent.opacity(hover ? 0.25 : 0.12))
                Text(role.rawValue).font(.system(size: 92, weight: .black, design: .rounded))
                    .foregroundStyle(accent.opacity(0.17)).padding(.trailing, 18).padding(.bottom, 34)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(hover ? 1 : 0.7), style: StrokeStyle(lineWidth: hover ? 4 : 2.5, dash: hover ? [] : [9, 5])))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: hoverBinding) { model.receive($0, role: role) }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    var model: Model?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        let model = Model(); self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 1050), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "NAS Icon Bridge \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"; window.contentView = NSHostingView(rootView: ContentView(model: model)); window.center(); window.makeKeyAndOrderFront(nil)
        window.delegate = self; self.window = window
        rebuildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .interfaceLanguageChanged, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showAbout() { model?.showingAbout = true }
    @objc func rebuildMenu() {
        let menu = NSMenu(); let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let about = NSMenuItem(title: tr("關於 NAS Icon Bridge"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self; appMenu.addItem(about); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("結束 NAS Icon Bridge"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: tr("編輯")); let editItem = NSMenuItem(title: tr("編輯"), action: nil, keyEquivalent: ""); editItem.submenu = editMenu; menu.addItem(editItem)
        editMenu.addItem(withTitle: tr("複製"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("全選"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.busy == true { model?.alert("操作仍在執行。請先停止後續項目，並等目前項目完成，再結束 App。"); return .terminateCancel }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.busy != true }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 16) {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: 100, height: 100)
            }
            Text("NAS Icon Bridge").font(.title.bold())
            Text(tr("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")"))
            Text(tr("製作者：Kevin"))
            Text(tr("版權所有 SPARKY")).font(.headline)
            Link("www.sparky.hk", destination: URL(string: "https://www.sparky.hk/")!)
            Button(tr("完成")) { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }.padding(30).frame(width: 490)
    }
}
