# 發佈交接／Release handoff

版本／Version：**1.0.1**（build 14）。

## 上傳原始碼／Upload source

解壓 source.zip，將內部 NASIconBridge 的內容作為公開儲存庫根目錄。上傳 Source/、Assets/、Resources/、README.md、TECHNICAL.md、LICENSE、CHANGELOG.md、RELEASE.md、build.command、release.command 及 .gitignore。介紹及技術說明必須保留逐節中英對照。

Extract source.zip and use the contents of its NASIconBridge folder as the public repository root. Upload the files and folders listed above. Preserve the paired Chinese and English introduction and technical documentation.

## 授權及聲明／License and notice

保留 Kevin、SPARKY、https://www.sparky.hk/ 及自訂 LICENSE。不得改成其他授權。標示個人家用、禁止商業使用、僅供測試，以及適用法律允許範圍內不承擔數據損失責任。不能宣稱保證資料安全或所有失敗可還原。

Retain Kevin, SPARKY, https://www.sparky.hk/ and the custom LICENSE. Do not substitute another license. State personal household use, no commercial use, testing only, and the data-loss liability limitation to the extent permitted by applicable law. Do not guarantee data safety or recovery from every failure.

## AFP 定位／AFP migration scope

Apple 自 macOS 27 起不支援 AFP。此工具須在仍可掛載 AFP 的 Mac 上使用，以便升級前把圖示遷移至 SMB；它不恢復 macOS 27 的 AFP 支援。官方來源見 README。

Apple ended AFP support with macOS 27. Use this utility on an AFP-capable Mac to migrate icons to SMB before upgrading; it does not restore AFP support to macOS 27. Official sources are linked in README.

## GitHub Release

建立 v1.0.1 tag 及 Release，附上 NASIconBridge-1.0.1-macOS-arm64.zip、NASIconBridge-1.0.1-source.zip 及 SHA256SUMS.txt。下載包為 Apple Silicon，遷移需可掛載 AFP 的 macOS 13–26；ad-hoc 簽名，尚未 Apple 公證。

Create a v1.0.1 tag and Release with the two ZIPs and SHA256SUMS.txt. The download targets Apple Silicon; migration requires AFP-capable macOS 13–26. It is ad-hoc signed and has not been Apple-notarized.

## 不公開的資料／Exclude private data

不要上傳 backup/、NAS 個人資料、last-run.json、selection.json、測試暫存及內部操作紀錄。App 及 ZIP 只作 Release 附件，不提交到原始碼儲存庫。

Do not upload backup/, personal NAS data, last-run.json, selection.json, test scratch files or internal operation logs. App binaries and ZIPs belong in Release attachments, not the source repository.

## 建置與驗證／Build and validation

在裝有 Xcode Command Line Tools 或 Xcode 的 Mac 上執行：

On a Mac with Xcode Command Line Tools or Xcode, run:

```sh
./build.command
"./NAS Icon Bridge.app/Contents/MacOS/NASIconBridge" --self-test
./release.command
```

按主機架構編譯；提供的下載包為 arm64。測試範圍及限制見 TECHNICAL.md。發布後檢查中英內容、授權、下載及校驗值，並回報儲存庫和 Release 網址。

Builds use the host architecture; the supplied download is arm64. See TECHNICAL.md for test scope and limitations. After publication, verify bilingual content, license, downloads and checksums, then report repository and Release URLs.

## App 與公開文件分工／App and public documentation

App 的 About 只顯示名稱、版本、Kevin／SPARKY 及網站；AFP 背景、功能、測試及責任聲明放在 README、TECHNICAL.md 及 LICENSE。

About shows only the name, version, Kevin / SPARKY credits and website. AFP background, features, testing notice and liability terms belong in README, TECHNICAL.md and LICENSE.
