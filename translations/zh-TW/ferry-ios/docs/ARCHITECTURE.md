# 架構

```
SwiftUI 檢視 ──> AppModel (@Observable，主執行緒)
                     │  SourceStore、Downloads、Keychain    (僅限 Swift)
                     ▼
                  Core.swift ── C ABI (JSON) ──> core/ (Rust, libferry_core.a)
                                                 ├ account   plume_core GrandSlam + 2FA, omnisette anisette v3
                                                 ├ device    idevice over TcpProvider(10.7.0.1, pairing file)
                                                 ├ inspect   zip + goblin + apple-codesign entitlements
                                                 ├ bundle    Info.plist 編輯、重新識別、注入 (plume_core MachO)
                                                 ├ install   xkit AutoSigner (憑證 + 簽署) → AppInstaller
                                                 └ library   保留的 IPA 檔案與選項，刷新
```

## 規則

- Core 擁有所有與 Apple 或裝置通訊的功能。Swift 從未直接操作 lockdown、憑證或 Mach-O 檔案；它只發送請求。
- 協定在 `core/src/protocol.rs` 中宣告一次。`App/Sources/Core/Protocol.swift`
  會鏡像對應，且除錯版本在啟動時會斷言兩者列出相同
  的方法 (`ferry_core_methods`)。
- 單一回呼承載所有事件：`result`、`error`、`progress`（帶有請求 ID）、`prompt`（2FA 程式碼、憑證撤銷，透過
  `ferry_core_respond` 回答）以及 `log`。
- 取消 Swift 任務會取消 core 的請求。
- Sources、downloads 和 Keychain 是應用程式的關注點並保留在 Swift 中；
  它們不需要 core。

## 生命週期

- Apple 工作階段無法持久化，因此 Apple ID 存在於 Keychain 中，
  core 會在啟動時重新登入。anisette 身分識別保存在
  `Application Support/Ferry/anisette` 中，因此 Apple 會持續信任該裝置並
  跳過 2FA。
- `Application Support/Ferry/library/<original id>/` 保留原始的 IPA、
  圖示和 `record.json`（安裝選項、到期日、授予的權限）；
  刷新就是使用相同選項從中重新安裝。
- 注入的微調會複製到 `Application Support/Ferry/tweaks/`，以便
  刷新時再次注入它們。
- Core 透過 (`device_lock`) 序列化安裝和刷新。

## 識別碼

免費的應用程式 ID 必須在每個團隊內唯一，因此應用程式以 `<id>.<TEAMID>` 安裝
（AltStore/SideStore 慣例）。巢狀延伸模組會在新前綴下保留其後綴。原始 ID 保存在 `FerryOriginalBundleIdentifier` 中。

## 尚未完成

- `.deb` 微調（僅限 `.dylib`/`.framework`）；自動打包 ElleKit 以支援
  Substrate 微調。
- 背景刷新（BGTaskScheduler 無法啟動 VPN）。
- 應用程式資料備份/還原、為其他應用程式啟用 JIT、在裝置上建立配對檔案。
