// Copyright (c) 2026 SPARKY. Created by Kevin.
// Personal household use only; commercial use prohibited. See LICENSE.
import AppKit
import Foundation

func selfTest() throws {
    let temp = fm.temporaryDirectory.appendingPathComponent("NASIconBridge-Test-" + UUID().uuidString)
    try fm.createDirectory(at: temp, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: temp) }
    let source = temp.appendingPathComponent("AFP")
    let target = temp.appendingPathComponent("SMB")
    try fm.createDirectory(at: source, withIntermediateDirectories: false)
    try fm.createDirectory(at: target, withIntermediateDirectories: false)
    var assertions = 0
    func expect(_ truth: Bool, _ message: String) throws { guard truth else { throw BridgeError("測試失敗：" + message) }; assertions += 1 }
    var rows: [ReportRow] = []
    var progressEvents: [WorkProgress] = []
    let engine = Engine(stop: StopToken(), progress: { progressEvents.append($0) }) { rows.append($0) }
    func make(_ root: URL, _ relative: String) throws -> URL { let u = root.appendingPathComponent(relative); try fm.createDirectory(at: u, withIntermediateDirectories: true); return u }
    let a = try make(source, "中文資料夾/子 目錄")
    let b = try make(target, "中文資料夾/子 目錄")
    let hiddenA = try make(source, ".隱藏目錄")
    _ = try make(target, ".隱藏目錄")
    _ = try make(source, "一般資料夾"); _ = try make(target, "一般資料夾")
    let missing = try make(source, "SMB 缺少")
    let image = NSImage(size: NSSize(width: 128, height: 128))
    image.lockFocus(); NSColor.systemOrange.setFill(); NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 120, height: 120), xRadius: 20, yRadius: 20).fill(); image.unlockFocus()
    try expect(NSWorkspace.shared.setIcon(image, forFile: a.path, options: []), "建立來源圖示")
    try expect(NSWorkspace.shared.setIcon(image, forFile: hiddenA.path, options: []), "建立隱藏目錄圖示")
    try expect(NSWorkspace.shared.setIcon(image, forFile: missing.path, options: []), "建立缺少對應目錄的圖示")
    var originalInfo = Data(count: 32); originalInfo[8] = 0x40; originalInfo[10] = 0x12
    try putAttribute(b, finderKey, originalInfo)
    try putAttribute(b, "user.NASIconBridge-test", Data("unrelated-metadata".utf8))
    let ordinary = b.appendingPathComponent("ordinary.txt"); try Data("重要一般檔案".utf8).write(to: ordinary)
    let original = try readState(b); let sourceOriginal = try readState(a)
    try fm.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: temp)
    let package = try make(source, "Ignore.app"); try expect(NSWorkspace.shared.setIcon(image, forFile: package.path, options: []), "建立套件圖示")
    let items = try engine.scan(source: source, destination: target)
    try expect(items.count == 2, "找到正常與隱藏圖示；略過套件及缺少目錄")
    try expect(rows.contains { $0.status == "掃描失敗" && $0.path == "SMB 缺少" }, "報告目標缺少")
    try expect(rows.contains { $0.status == "略過" && $0.detail == "符號連結" }, "略過符號連結")
    try expect(try readState(b) == original, "Dry run 不更改目標")
    try expect(try readState(a) == sourceOriginal, "掃描不更改來源")
    try engine.probe(target)
    try expect(!(try fm.contentsOfDirectory(atPath: target.path)).contains { $0.hasPrefix(".NASIconBridge-Probe-") }, "清理測試目錄")
    let backup = temp.appendingPathComponent("Backup")
    try engine.apply(items, source: source, destination: target, backup: backup)
    let applied = try readState(b)
    try expect(hasCustom(applied.finder), "套用 custom icon 旗標")
    try expect(applied.finder?[10] == 0x12 && applied.finder?[8] == 0x44, "保留其他 FinderInfo 位元")
    try expect(applied.resource == original.resource, "不覆蓋資料夾原有 resource fork")
    try expect(try attribute(b, "user.NASIconBridge-test") == Data("unrelated-metadata".utf8), "保留無關 metadata")
    try expect(applied.carrier?.attributes[resourceKey] == sourceOriginal.carrier?.attributes[resourceKey], "原樣移轉圖示 resource fork")
    try expect(try Data(contentsOf: ordinary) == Data("重要一般檔案".utf8), "一般檔案內容不變")
    try expect(try readState(a) == sourceOriginal, "本機獨立來源不變")
    let manifest = try engine.load(backup)
    try expect(manifest.entries.count == 2 && manifest.entries.allSatisfy { $0.phase == "applied" }, "完整備份與記錄")
    try engine.restore(backup: backup, destination: target, dryRun: true, recoverInterrupted: false)
    try expect(try readState(b) == applied, "還原 Dry run 不寫入")
    try engine.restore(backup: backup, destination: target, dryRun: false, recoverInterrupted: false)
    try expect(try readState(b) == original, "完整還原原有 FinderInfo／folder fork／Icon 缺席狀態")
    // Guard against stale scans and refuse writes before backup if destination changed.
    let again = try engine.scan(source: source, destination: target)
    var changed = originalInfo; changed[10] = 0x13; try putAttribute(b, finderKey, changed)
    do { try engine.apply(again, source: source, destination: target, backup: temp.appendingPathComponent("Stale")); throw BridgeError("應拒絕已變動的目標") }
    catch { try expect(error.localizedDescription.contains("已於掃描後變動"), "套用前重新檢查目標") }
    try putAttribute(b, finderKey, originalInfo)
    // Existing destination icon is backed up and restored byte for byte.
    let oldImage = NSImage(named: NSImage.cautionName)!
    try expect(NSWorkspace.shared.setIcon(oldImage, forFile: b.path, options: []), "建立目標舊圖示")
    let old = try readState(b)
    let again2 = try engine.scan(source: source, destination: target)
    let backup2 = temp.appendingPathComponent("Backup2")
    try engine.apply(again2, source: source, destination: target, backup: backup2)
    try expect(try engine.load(backup2).entries.allSatisfy { $0.phase == "applied" }, "覆蓋不同大小既有圖示成功")
    let newState = try readState(b)
    var changed2 = newState.finder!; changed2[10] = 0x42; try putAttribute(b, finderKey, changed2)
    rows = []
    try engine.restore(backup: backup2, destination: target, dryRun: false, recoverInterrupted: false)
    try expect(rows.contains { $0.status == "還原失敗" }, "不覆蓋套用後已更改的 metadata")
    try putAttribute(b, finderKey, newState.finder)
    try engine.restore(backup: backup2, destination: target, dryRun: false, recoverInterrupted: false)
    try expect(try readState(b) == old, "原樣還原目標原有圖示與全部 carrier metadata")
    // Malicious backup paths cannot escape the selected root.
    var bad = Manifest(destinationRoot: target.path, sourceRoot: source.path)
    bad.entries = [Entry(relative: "../escape", original: original, source: sourceOriginal, expected: nil, phase: "writing")]
    let badBundle = temp.appendingPathComponent("Bad"); try fm.createDirectory(at: badBundle, withIntermediateDirectories: false); try engine.save(bad, at: badBundle)
    rows = []; try engine.restore(backup: badBundle, destination: target, dryRun: false, recoverInterrupted: true)
    try expect(rows.contains { $0.detail.contains("不安全") }, "拒絕備份路徑穿越")
    // Never overwrite nonempty carrier data, even when someone names a normal file Icon CR.
    let carrier = b.appendingPathComponent(carrierName); try Data("使用者資料".utf8).write(to: carrier)
    let collision = try engine.scan(source: source, destination: target)
    rows = []; try engine.apply(collision, source: source, destination: target, backup: temp.appendingPathComponent("Collision"))
    try expect(try Data(contentsOf: carrier) == Data("使用者資料".utf8), "保護非空 Icon 檔案")
    try expect(rows.contains { $0.detail.contains("含有資料") }, "明確回報衝突")
    // Read-only carrier: failed writes must roll back without touching normal files.
    try Data().write(to: carrier)
    try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: carrier.path)
    let readOnly = try readState(b)
    let readOnlyItems = try engine.scan(source: source, destination: target)
    rows = []; try engine.apply(readOnlyItems, source: source, destination: target, backup: temp.appendingPathComponent("ReadOnly"))
    try expect(rows.contains { $0.status == "失敗／已回復" }, "寫入失敗會自動回復")
    try expect(try readState(b) == readOnly, "失敗回復保留原始 metadata 及權限")
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: carrier.path)
    // Linked carriers must never modify the linked user file.
    try fm.removeItem(at: carrier)
    let linkedData = b.appendingPathComponent("linked-original.txt")
    try Data("linked-user-data".utf8).write(to: linkedData)
    try fm.linkItem(at: linkedData, to: carrier)
    do { _ = try readState(b); throw BridgeError("應拒絕硬連結") } catch { try expect(error.localizedDescription.contains("硬連結"), "拒絕圖示 carrier 硬連結") }
    try fm.removeItem(at: carrier)
    try expect(try Data(contentsOf: linkedData) == Data("linked-user-data".utf8), "硬連結一般檔案保持原樣")
    // Destination symlink and interrupted journal handling.
    try fm.createSymbolicLink(at: target.appendingPathComponent("outside"), withDestinationURL: source)
    do { _ = try checked(target, "outside"); throw BridgeError("應拒絕符號連結") } catch { try expect(error.localizedDescription.contains("符號連結"), "拒絕目標符號連結") }
    let interruptedBundle = temp.appendingPathComponent("Interrupted"); try fm.createDirectory(at: interruptedBundle, withIntermediateDirectories: false)
    var interrupted = Manifest(destinationRoot: target.path, sourceRoot: source.path)
    interrupted.entries = [Entry(relative: "一般資料夾", original: IconState(finder: nil, resource: nil, carrier: nil), source: sourceOriginal, expected: nil, phase: "writing")]
    try engine.save(interrupted, at: interruptedBundle)
    rows = []; try engine.restore(backup: interruptedBundle, destination: target, dryRun: false, recoverInterrupted: false)
    try expect(rows.contains { $0.detail.contains("上次寫入中斷") }, "中斷寫入需明確啟用復原")
    rows = []; try engine.restore(backup: interruptedBundle, destination: target, dryRun: false, recoverInterrupted: true)
    try expect(rows.contains { $0.status == "已還原" }, "可復原中斷寫入")
    // Native rendered-image fallback when a custom flag exists without a readable carrier.
    let nativeSource = try make(source, "原生備援")
    let nativeTarget = try make(target, "原生備援")
    try putAttribute(nativeSource, finderKey, withCustomFlag(nil))
    let nativeOriginal = try readState(nativeTarget)
    let nativeItems = try engine.scan(source: source, destination: target).filter { $0.relative == "原生備援" }
    try expect(nativeItems.count == 1 && nativeItems[0].imageTIFF != nil, "保存原生圖示影像備援")
    let nativeBackup = temp.appendingPathComponent("NativeBackup")
    try engine.apply(nativeItems, source: source, destination: target, backup: nativeBackup)
    try expect(hasCustom(try readState(nativeTarget).finder), "原生 setIcon 備援可套用")
    try engine.restore(backup: nativeBackup, destination: target, dryRun: false, recoverInterrupted: false)
    try expect(try readState(nativeTarget) == nativeOriginal, "原生備援可還原")
    // Probe failure never modifies existing folder metadata.
    let blocked = try make(target, "禁止寫入")
    let blockedState = try readState(blocked)
    try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blocked.path)
    do { try engine.probe(blocked); throw BridgeError("應拒絕無寫入權限的目標") }
    catch { try expect(try readState(blocked) == blockedState, "檢測失敗不修改現有圖示") }
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path)
    // Finder drag representations and protocol classification.
    let drop = URL(fileURLWithPath: "/Volumes/中文資料夾/含 空白", isDirectory: true)
    try expect(droppedURL(drop) == drop, "接受 Finder URL 拖放")
    try expect(droppedURL(drop.dataRepresentation) == drop, "接受 percent-encoded file URL 資料")
    try expect(droppedURL(drop.absoluteString) == drop, "接受 file URL 字串")
    try expect(droppedURL("smb://server/share") == nil, "不把未掛載 smb 網址當資料夾")
    try expect(protocolName("afpfs") == "AFP" && protocolName("smbfs") == "SMB", "依實際檔案系統識別協定")
    do { _ = try selectedNetworkDirectory(source, role: .afp); throw BridgeError("應拒絕把本機磁碟當 AFP") }
    catch { try expect(error.localizedDescription.contains("這個區域需要 AFP"), "拒絕放入錯誤協定") }
    guard let reference = (source as NSURL).fileReferenceURL() else { throw BridgeError("無法建立 Finder 檔案參照 URL") }
    try expect(try selectedDirectory(reference) == selectedDirectory(source), "解析 Finder 檔案參照 URL")
    let alias = temp.appendingPathComponent("Finder Alias")
    let bookmark = try source.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
    try URL.writeBookmarkData(bookmark, to: alias)
    try expect(try selectedDirectory(alias) == selectedDirectory(source), "解析 Finder 桌面替身")
    // One-button orchestration: scanning, backups, transfer and restore.
    let flowSource = try make(temp, "FlowAFP")
    let flowTarget = try make(temp, "FlowSMB")
    let flowA = try make(flowSource, "下一層/圖示")
    let flowB = try make(flowTarget, "下一層/圖示")
    try expect(NSWorkspace.shared.setIcon(image, forFile: flowA.path, options: []), "建立下層流程圖示")
    let flowOriginal = try readState(flowB)
    let dryBackup = temp.appendingPathComponent("MustNotExist")
    progressEvents = []
    let preview = try engine.process(source: flowSource, destination: flowTarget, dryRun: true, backup: dryBackup)
    try expect(preview.count == 1 && !fm.fileExists(atPath: dryBackup.path), "一鍵 Dry run 不建立備份或寫入目標")
    try expect(try readState(flowB) == flowOriginal, "一鍵 Dry run 保留原始目標")
    try expect(progressEvents.first?.total == nil && progressEvents.first?.stage == "掃描資料夾", "掃描總數未知時不顯示虛假百分比")
    try expect(progressEvents.last?.stage == "掃描完成" && progressEvents.last?.completed == 3, "掃描完成回報實際目錄數")
    let flowBackup = temp.appendingPathComponent("FlowBackup")
    progressEvents = []
    _ = try engine.process(source: flowSource, destination: flowTarget, dryRun: false, backup: flowBackup)
    try expect(try engine.load(flowBackup).entries.allSatisfy { $0.phase == "applied" } && hasCustom(readState(flowB).finder), "一鍵流程完成遞迴、備份及套用")
    try expect(progressEvents.contains { $0.stage == "保存本機備份" && $0.completed == 1 && $0.total == 1 }, "備份顯示已保存／總數")
    try expect(progressEvents.last?.stage == "套用及驗證圖示" && progressEvents.last?.fraction == 1, "套用進度只在驗證後完成")
    try engine.restore(backup: flowBackup, destination: flowTarget, dryRun: false, recoverInterrupted: false)
    try expect(try readState(flowB) == flowOriginal, "一鍵流程產生的備份可還原")
    // AFP directory fork absence must not be confused with a denied Icon file fork.
    var readAttempted = false
    let absentFork = try directoryResource(source, names: [finderKey]) { _, _ in readAttempted = true; throw BridgeError("Operation not permitted") }
    try expect(absentFork == nil && !readAttempted, "不讀取未列出的資料夾 resource fork，避免 AFP EPERM")
    let advertisedFork = try directoryResource(source, names: [resourceKey]) { _, _ in Data("folder-fork".utf8) }
    try expect(advertisedFork == Data("folder-fork".utf8), "存在的資料夾 fork 仍會讀取及備份")
    do {
        _ = try directoryResource(source, names: [resourceKey]) { _, _ in throw BridgeError("Operation not permitted") }
        throw BridgeError("不應忽略已列出 fork 的讀取失敗")
    } catch { try expect(error.localizedDescription == "Operation not permitted", "不隱藏真正的 fork 權限錯誤") }
    try expect(progressEvents.last?.stage == "還原並驗證圖示" && progressEvents.last?.fraction == 1, "還原有完成進度")
    try expect(WorkProgress(stage: "test", completed: 2, total: 4, detail: "").fraction == 0.5, "計算真實處理比例")
    try expect(WorkProgress(stage: "test", completed: 0, total: 0, detail: "").fraction == nil, "零項目不產生無效百分比")
    let eligible = ReportRow(path: "folder", status: "可套用", detail: "")
    let good = ReportRow(path: "folder", status: "成功", detail: "")
    let failedRow = ReportRow(path: "other", status: "失敗／已回復", detail: "")
    let previewResult = resultSummary(kind: .preview, rows: [eligible], failure: nil)
    try expect(previewResult.message.contains("預覽完成") && previewResult.message.contains("尚未寫入 NAS"), "完成預覽不誤報已套用")
    try expect(resultSummary(kind: .apply, rows: [good], failure: nil).message.contains("套用完成"), "正式套用明確顯示完成")
    try expect(resultSummary(kind: .apply, rows: [good, failedRow], failure: nil).state == "partial", "有失敗項目時標記部分完成")
    try expect(resultSummary(kind: .preview, rows: [], failure: "已停止").state == "stopped", "停止不誤報完成")
    try expect(resultSummary(kind: .apply, rows: [], failure: "server failure").state == "failed", "錯誤不誤報完成")
    let record = SavedRun(finished: Date(), kind: .preview, state: previewResult.state, summary: previewResult.message, source: flowSource.path, target: flowTarget.path, backup: nil, rows: [eligible])
    let recorded = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(SavedRun.self, from: recorded)
    try expect(decoded.kind == .preview && decoded.summary == record.summary && decoded.rows.count == 1, "上次結果能保存及載入")
    let stopped = StopToken(); stopped.stop()
    do { _ = try Engine(stop: stopped, emit: { _ in }).scan(source: source, destination: target); throw BridgeError("應停止") }
    catch { try expect(error.localizedDescription.contains("已停止"), "取消操作") }
    let originalLanguage = Localization.shared.language
    Localization.shared.language = "en"
    defer { Localization.shared.language = originalLanguage }
    try expect(tr("測試掃描") == "Preview scan", "English main action")
    try expect(tr("已處理 3／12 項") == "Processed 3 / 12 items", "Interpolated progress translation")
    try expect(tr("最近備份：/tmp/成功/{0}") == "Latest backup: /tmp/成功/{0}", "Translation preserves folder names and placeholder-like text")
    try expect(tr("部分完成：成功 4 項；失敗 2 項，請查看清單。Finder 顯示仍需確認。") == "Partially complete: 4 succeeded; 2 failed, review the list. Check Finder appearance separately.", "English partial result and nested failure count")
    try expect(tr("已確認 AFP：/Volumes/中文共享。兩側請選擇相同層級的資料夾。") == "Verified AFP: /Volumes/中文共享. Choose the same folder level on both sides.", "English selection with original path")
    try expect(tr("關於 NAS Icon Bridge") == "About NAS Icon Bridge", "English About menu")
    Localization.shared.language = "zh-Hant"
    try expect(tr("測試掃描") == "測試掃描", "Switch back to Traditional Chinese")
    print("PASS: \(assertions) assertions; isolated local filesystem; no NAS folders modified.")
}
