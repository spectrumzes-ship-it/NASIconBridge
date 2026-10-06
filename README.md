# NAS Icon Bridge 1.0.1

**僅供測試、僅限個人家用，禁止商業使用。**

**For testing and personal household use only. Commercial use is prohibited.**

## 介紹／Introduction

NAS Icon Bridge 是由 Kevin 製作的原生 macOS 工具，協助將 AFP 掛載中可見的 Finder 自訂資料夾圖示，備份並批量複製或重新套用到對應的 SMB 資料夾。以 Swift、SwiftUI 及 AppKit 製作，適合家庭 NAS 使用者在改用 SMB 前遷移原有圖示。

NAS Icon Bridge is a native macOS utility created by Kevin. It backs up and transfers or reapplies Finder custom folder icons from AFP mounts to matching SMB folders. Built with Swift, SwiftUI and AppKit, it helps home NAS users migrate existing icons before switching to SMB.

## AFP 停止支援背景／Why AFP migration is needed

Apple 從 **macOS 27** 起不再支援 AFP，包括 NAS 的一般資料傳輸。macOS 27 於 **2026 年 9 月 14 日**正式發布。[Apple AFP 支援說明](https://support.apple.com/en-us/102423)、[發布日期](https://support.apple.com/en-us/149035)。

Apple no longer supports AFP starting with **macOS 27**, including ordinary NAS data transfers. macOS 27 was released on **September 14, 2026**. See [Apple AFP guidance](https://support.apple.com/en-us/102423) and [the release date](https://support.apple.com/en-us/149035).

部分 NAS 的 AFP／SMB metadata 處理不同，原本可見的圖示可能在改用 SMB 後消失。此工具嘗試保留這些圖示，**不會恢復 macOS 27 的 AFP 支援**。請在仍能同時掛載 AFP 及 SMB 的 Mac（例如 macOS 13–26）上遷移；若已升級，需使用另一台仍支援 AFP 的 Mac。

Some NAS servers expose icon metadata differently over AFP and SMB, so existing icons may disappear when switching. This utility attempts to preserve them; **it does not restore AFP support to macOS 27**. Migrate on a Mac that can still mount both AFP and SMB, such as macOS 13–26. If already upgraded, use another AFP-capable Mac.

## 測試聲明及責任限制／Testing notice and limitation of liability

**本工具僅供測試，按現狀提供，不保證適用於所有 NAS、系統或資料。使用者須自行評估風險，先備份重要資料，並以少量非重要資料夾測試。於適用法律允許的範圍內，Kevin、SPARKY 及貢獻者不對使用或無法使用本工具所造成的數據遺失、損毀、圖示或 metadata 改變，以及其他損失承擔責任。**

**This utility is provided AS IS for testing only. Compatibility with every NAS, system or dataset is not guaranteed. Users must assess the risks, back up important data independently and test on a small set of non-critical folders first. To the extent permitted by applicable law, Kevin, SPARKY and contributors accept no liability for data loss, corruption, changes to icons or metadata, or other losses arising from use of or inability to use this utility.**

工具建立的備份主要保存圖示及相關 metadata，**不是 NAS 的完整資料備份**，不能取代你自己的檔案備份。

The utility's backups primarily preserve icons and related metadata. **They are not complete NAS data backups** and do not replace your own file backups.

## 功能／Features

| 繁體中文 | English |
| --- | --- |
| 藍色 AFP、青綠色 SMB 拖放區及背景水印 | Blue AFP and teal SMB drop areas with watermarks |
| 驗證掛載協定，遞迴掃描並按相對路徑對應 | Mount protocol verification, recursive scanning and relative-path matching |
| 分開測試掃描及正式套用 | Separate preview and apply actions |
| SMB metadata 能力檢測及讀回驗證 | SMB metadata capability tests and read-back verification |
| 備份、還原、進度及結果匯出 | Backups, restore, progress and result export |
| 即時切換繁體中文／英文及 About | Immediate Traditional Chinese / English switching and About |
| 啟動時不帶入上次 AFP／SMB 選擇，清除舊結果 | Empty AFP/SMB selections on launch; previous results cleared |

## 下載與操作／Download and use

從此儲存庫的 **Releases** 下載 `NASIconBridge-1.0.1-macOS-arm64.zip`，解壓至可寫入的 Mac 本機資料夾，開啟 `NAS Icon Bridge.app`。下載包為 Apple Silicon，最低部署目標 macOS 13；AFP 遷移需系統仍支援 AFP，通常為 macOS 13–26。

Download `NASIconBridge-1.0.1-macOS-arm64.zip` from **Releases**, extract it to a writable local Mac folder and open `NAS Icon Bridge.app`. The download targets Apple Silicon with a minimum deployment target of macOS 13. AFP migration requires an AFP-capable system, typically macOS 13–26.

| 步驟 | 繁體中文 | English |
| --- | --- | --- |
| 1 | 同時掛載同一個 NAS 共享的 AFP 及 SMB | Mount the same NAS share using AFP and SMB |
| 2 | 將同一層級的 AFP／SMB 資料夾拖到對應區域 | Drop matching folder roots at the same level into their areas |
| 3 | 按「測試掃描」，只預覽，不寫入 NAS | Choose Preview scan; no NAS writes |
| 4 | 按「正式套用」，檢測、備份、寫入及驗證 | Choose Apply icons to test, back up, write and verify |
| 5 | 查看清單，並在 Finder 確認 SMB 圖示 | Review results and verify SMB icons in Finder |

## 備份與還原／Backups and restore

新備份存放在 App 同一層的 `backup/`，每次正式操作建立獨立子資料夾。備份必須存於本機 APFS／HFS+；位置不能寫入時會停止。按「顯示備份」開啟，或按「從備份還原」選擇包含 `manifest.json` 的備份資料夾。請完整保留所有備份檔案。清除結果不會刪除備份。

New backups go to `backup/` beside the app, with a separate subfolder per apply operation. Backups must be on local APFS/HFS+; the operation stops if the location is not writable. Use Show backups or Restore from backup and choose a folder containing `manifest.json`. Preserve every backup file. Clearing results does not delete backups.

AFP 與 SMB 可能指向同一份底層資料，因此 SMB 寫入或還原圖示亦可能反映於 AFP。成功只代表 metadata 讀回驗證通過；Finder 快取及重新掛載後的持久性須另行確認。

AFP and SMB may expose the same underlying data, so SMB icon writes and restores may also appear over AFP. Success only confirms metadata read-back. Finder caching and persistence after remounting need separate checks.

## 技術說明與建置／Technical documentation and build

詳細流程、metadata、備份格式及限制見 [TECHNICAL.md](TECHNICAL.md)，採中英逐節對照。

See [TECHNICAL.md](TECHNICAL.md) for the workflow, metadata, backup format and limitations, with paired Chinese and English sections.

在裝有 Xcode Command Line Tools 或 Xcode 的 Mac 上執行以下指令。按主機架構編譯；所提供的下載包為 arm64。

Run the following on a Mac with Xcode Command Line Tools or Xcode. Builds use the host architecture; the supplied download is arm64.

```sh
./build.command
"./NAS Icon Bridge.app/Contents/MacOS/NASIconBridge" --self-test
./release.command
```

`release.command` 會重新建置 App，並在 `dist/` 產生 App ZIP、原始碼 ZIP 及包含兩者的 `SHA256SUMS.txt`。原始碼包只包含指定的公開檔案；壓縮包不包含 macOS 延伸屬性、ACL 或 AppleDouble metadata。

`release.command` rebuilds the App and creates the App ZIP, source ZIP and checksums for both in `dist/`. The source archive includes only the designated public files. Archives exclude macOS extended attributes, ACLs and AppleDouble metadata.

目前採 ad-hoc 簽名，**尚未完成 Developer ID 簽名或 Apple 公證**；並非已公證的正式產品。

The current binary is ad-hoc signed and **has not been Developer ID signed or Apple-notarized**. It is not a notarized production release.

## 授權與作者／License and credits

僅限個人家用、非商業測試。程式碼公開供閱讀、下載及依 [LICENSE](LICENSE) 修改及免費分享，須保留授權及作者資訊。這是 source-available 專案，並非 OSI 認可的開源授權。禁止商業、職業、公司、客戶服務及組織用途，除非另取得書面許可。

Personal household, non-commercial testing only. Source is publicly available for inspection, downloading, modification and free redistribution under [LICENSE](LICENSE), with license and attribution retained. This is a source-available project, not an OSI-approved open-source license. Commercial, professional, business, client and organizational use require separate written permission.

製作者／Created by：**Kevin**  
版權所有／Copyright：**SPARKY**  
網站／Website：[www.sparky.hk](https://www.sparky.hk/)
