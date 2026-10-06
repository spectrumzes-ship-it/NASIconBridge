# 技術說明／Technical documentation

Version：**1.0.1**。僅供個人家用測試；禁止商業使用。

Version: **1.0.1**. For personal household testing only; commercial use is prohibited.

## 1. 平台及組件／Platform and components

使用 Swift、SwiftUI、AppKit、Foundation 及 Darwin 系統 API。`App.swift` 提供介面及背景工作管理；`Engine.swift` 處理掃描、metadata、備份及還原；`Localization.swift` 翻譯顯示文字；`SelfTest.swift` 提供本機隔離測試。沒有第三方執行期套件依賴。

The app uses Swift, SwiftUI, AppKit, Foundation and Darwin APIs. `App.swift` manages the UI and background jobs; `Engine.swift` implements scanning, metadata, backups and restore; `Localization.swift` translates presentation strings; `SelfTest.swift` provides isolated local tests. There are no third-party runtime package dependencies.

## 2. 掛載與對應／Mounts and matching

以 `statfs` 識別 `afpfs`／`smbfs`，不依賴磁碟名稱或 `-1` 尾碼。App 不會掛載 NAS，也不恢復上次 AFP／SMB 選擇；選單只列出目前已掛載的共享。兩個根目錄須指向同一共享及同一層級，以相對路徑對應，不自動改名或推測其他資料夾。

`statfs` identifies `afpfs` and `smbfs`, independently of mount names or a `-1` suffix. The app does not mount NAS shares or restore previous AFP/SMB selections. Menus only list currently mounted shares. Roots must refer to the same share and level. Matching uses relative paths without renaming or guessing alternative folders.

根目錄、隱藏資料夾及子資料夾會掃描；符號連結及套件內部會略過。路徑會驗證，拒絕 `..`、絕對相對路徑及指向其他位置的符號連結。圖示 carrier 若不是一般檔案、有硬連結或含不應覆蓋的資料，會拒絕或略過操作。

The root, hidden folders and subfolders are scanned; symbolic links and package interiors are skipped. Path checks reject `..`, absolute relative paths and symbolic links pointing elsewhere. Icon carriers that are not regular files, have hard links or contain data that should not be overwritten are refused or skipped.

## 3. 圖示 metadata／Icon metadata

| 項目／Item | 繁體中文 | English |
| --- | --- | --- |
| `com.apple.FinderInfo` | 32-byte Finder 資訊，含自訂圖示旗標 | 32-byte Finder metadata containing the custom icon flag |
| `Icon\r` | 檔名末尾是 carriage return 的專用圖示 carrier | Dedicated icon carrier with a carriage return at the end of its name |
| `com.apple.ResourceFork` | carrier 的原始圖示資料 | Raw icon data in the carrier's resource fork |
| `NSWorkspace.setIcon` | 原始 fork 缺失時的原生圖示重建備援 | Native reconstruction fallback when the original fork is unavailable |

優先複製原始 carrier resource fork；保留目標資料夾其他 FinderInfo 位元，只加入自訂圖示旗標。重建備援以來源渲染影像重新生成，可能無法保留全部原始表示。沒有原始 fork，且 SMB 不支援原生重建時，該項目會失敗並保持不變。

Raw carrier resource forks are preferred. Other destination folder FinderInfo bits are preserved while the custom icon flag is added. Reconstruction uses a rendered source image and may not preserve every original representation. If no raw fork is available and SMB fails native reconstruction testing, the item fails and remains unchanged.

AFP 目錄可能拒絕讀取不存在的 resource fork，因此只讀取實際列出的目錄 fork。SMB 不存在屬性的長度查詢與實際讀取可能不一致；實際讀取回報 ENOATTR 時視為不存在。長度變動會有限次重試，寫入後仍須精確比較。

AFP directories may reject reads of absent resource forks, so directory forks are read only when advertised. SMB size queries and reads may disagree for absent attributes; ENOATTR on the actual read is treated as absent. Changing lengths receive bounded retries, while written values still require exact verification.

替換較大的舊 resource fork 時，先開啟 existing named fork，再以 `ftruncate` 清除舊長度，避免較短的新圖示殘留舊資料。伺服器不支援必要操作時會回報失敗，不能保證所有 NAS 相容。

When replacing a larger old resource fork, the existing named fork is opened and truncated using `ftruncate` before replacement, preventing trailing data behind a smaller new icon. Unsupported server operations are reported as failures; compatibility with every NAS is not guaranteed.

## 4. 正式流程／Apply workflow

1. 掃描及收集對應圖示。／Scan and collect matching icons.
2. 在唯一暫存資料夾檢測 FinderInfo、resource fork、縮短寫入及原生重建，測試後清除。／Test FinderInfo, resource forks, shortening and native reconstruction in a unique temporary folder, then remove it.
3. 核對來源及目標仍與掃描時一致。／Verify source and destination still match their scan-time states.
4. 在修改既有圖示前，保存所有來源快照及目標原始 metadata。／Save all source snapshots and original destination metadata before modifying existing icons.
5. 逐項寫入、讀回驗證及更新備份日誌。／Write each item, verify read-back and update the backup journal.
6. 單項失敗時嘗試回復；回復失敗則停止後續寫入。／Attempt rollback after an item failure; stop subsequent writes if rollback fails.

「測試掃描」完全唯讀，不建立 NAS 檢測資料夾。獨立「檢測 SMB 支援」及正式套用會寫入唯一暫存測試目錄。停止按鈕只停止後續項目，必須等待正在執行的系統呼叫返回。

Preview scan is entirely read-only and does not create NAS probe folders. The separate SMB support test and Apply action write to a unique temporary probe directory. Stop only halts subsequent items; the current system call must return first.

## 5. 備份格式及還原／Backup format and restore

每次正式操作在 App 同層的 `backup/` 建立獨立子資料夾。`manifest.json` 記錄版本、原始根目錄及項目數；`entry-N.json` 保存每項原始圖示 state、來源快照、預期結果及階段。二進位資料以 Base64 放入 JSON。所有檔案須完整保留。

Each Apply operation creates a separate subfolder in `backup/` beside the app. `manifest.json` records the format version, original roots and item count; `entry-N.json` stores each original icon state, source snapshot, expected result and phase. Binary values are encoded as Base64 within JSON. Preserve every file.

還原需使用備份記錄中的 SMB 根目錄，並會驗證路徑及目前 metadata，拒絕覆蓋後來改動的圖示。中斷寫入復原另有選項。此備份只涵蓋圖示及相關 metadata，**不是完整文件或 NAS 備份**。

Restore requires the recorded SMB root and checks paths and current metadata, refusing to overwrite icons modified afterwards. Interrupted-write recovery is a separate option. These backups cover icons and related metadata only; **they are not full file or NAS backups**.

## 6. 語言及資料保存／Language and stored data

顯示文字可即時切換繁體中文／英文，選擇保存在 UserDefaults。引擎使用穩定的內部狀態文字；翻譯只用於顯示及匯出，不更改資料夾名稱、相對路徑或備份對應。啟動時清除上次結果，目錄選擇保持空白；最近備份位置只留在本次工作階段，不再自動保存結果或路徑紀錄。備份 manifest 中仍保留還原所需的根目錄資訊。

Presentation switches immediately between Traditional Chinese and English, with the choice saved in UserDefaults. The engine retains stable internal statuses; translation is applied to display and export only, not folder names, relative paths or backup matching. Previous results are cleared on launch and mount selections start empty. The latest backup location stays in the current session only; automatic result and path logs are no longer saved. Backup manifests still retain the root information necessary for restoration.

## 7. 驗證及限制／Validation and limitations

76 項本機隔離測試曾通過，涵蓋掃描、複製、備份、還原、特殊路徑及翻譯。這不能代表已測試所有 NAS、斷線、權限或檔案系統。metadata 驗證成功不等於 Finder 已刷新，亦不保證重新掛載後持久保存。本次文件及聲明更新沒有重新執行 NAS 遷移。

76 isolated local assertions previously passed, covering scanning, transfer, backups, restore, special paths and translation. This does not cover every NAS, disconnection, permission or filesystem. Successful metadata verification does not mean Finder has refreshed or guarantee persistence after remounting. This documentation and notice update did not repeat NAS migration.

## 8. 測試及數據損失聲明／Testing and data-loss notice

**僅供測試，按現狀提供。請自行備份重要資料並先用非重要資料夾測試。於適用法律允許的範圍內，Kevin、SPARKY 及貢獻者不對使用或無法使用本工具引致的數據遺失、損毀、圖示或 metadata 改變，以及其他損失承擔責任。不保證所有失敗皆可回復。完整條款見 LICENSE。**

**For testing only; provided AS IS. Back up important data independently and test with non-critical folders first. To the extent permitted by applicable law, Kevin, SPARKY and contributors accept no liability for data loss, corruption, icon or metadata changes, or other losses arising from use of or inability to use this utility. Recovery from every failure is not guaranteed. See LICENSE for the full terms.**

## 9. 私隱及發布清理／Privacy and release hygiene

路徑提示使用通用 /Volumes/NAS，不包含製作者的真實共享名稱。App 不自動保存操作結果或目錄選擇；啟動時移除舊 last-run.json、selection.json。使用者主動匯出的報告及還原備份可能包含真實路徑，請勿公開。發布包排除個人備份、操作紀錄、.DS_Store、AppleDouble、延伸屬性及 ACL metadata；語言偏好仍保存在本機。

Path examples use generic /Volumes/NAS rather than the creator's real share names. The app does not automatically persist results or selections; legacy last-run.json and selection.json are removed on launch. User-exported reports and restore backups may contain actual paths and must not be published. Release packages exclude personal backups, operation logs, .DS_Store, AppleDouble, extended attributes and ACL metadata. Language preference remains local.
