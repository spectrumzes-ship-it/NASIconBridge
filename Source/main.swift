// Copyright (c) 2026 SPARKY. Created by Kevin.
// Personal household use only; commercial use prohibited. See LICENSE.
import AppKit
if CommandLine.arguments.contains("--self-test") {
    do { try selfTest(); exit(0) } catch { fputs("FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--diagnose-state") {
    do {
        guard CommandLine.arguments.count == 4 else { throw BridgeError("用法：--diagnose-state AFP資料夾 SMB資料夾；此診斷完全唯讀，不遞迴") }
        for (label, path) in zip(["AFP", "SMB"], CommandLine.arguments.suffix(2)) {
            let url = try selectedDirectory(URL(fileURLWithPath: path, isDirectory: true))
            let state = try readState(url)
            print("\(label)：\(url.path)〔\(protocolName(fileSystem(url)))〕；自訂旗標：\(hasCustom(state.finder))；Icon carrier：\(state.carrier != nil)；carrier fork：\(state.carrier?.attributes[resourceKey]?.count ?? 0) bytes；資料夾 fork：\(state.resource?.count ?? 0) bytes")
        }
        exit(0)
    } catch { fputs("診斷失敗：\(error.localizedDescription)\n", stderr); exit(1) }
}
if CommandLine.arguments.contains("--probe") {
    do {
        guard CommandLine.arguments.count == 3 else { throw BridgeError("用法：--probe SMB資料夾；只寫入獨立暫存測試目錄") }
        let engine = Engine(stop: StopToken(), emit: { print($0.detail) })
        try engine.probe(URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true))
        exit(0)
    } catch { fputs("檢測失敗：\(error.localizedDescription)\n", stderr); exit(1) }
}
MainActor.assumeIsolated {
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppDelegate()
application.delegate = delegate
application.run()

}
