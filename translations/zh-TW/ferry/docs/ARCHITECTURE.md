# 架構

Ferry 執行 Jimpactor 所做的功能（簽署 IPA、透過 USB/Wi-Fi 安裝它們，以及管理裝置），並且其設計旨在避免 Jimpactor 累積的結構問題。本檔案列出這些問題及取代每個問題的規則。

## Jimpactor 的問題，以及其取代方案

1. GUI 程序即為後端。
   裝置發現、工作執行緒和安裝都位於 `iced` 應用程式內部。其他工具（idl、`jimpactor-cli tray`）只能透過新增到重新啟動監聽器的 IPC 通道來存取該狀態：TCP 在 127.0.0.1 上，以及一個連接埠檔案和一個權杖檔案。如果視窗未執行，`idl install` 會失敗並顯示「無法連線至 Jimpactor」。

   Ferry：`ferryd` 擁有裝置和工作。GUI 和 CLI 是位於 `$XDG_RUNTIME_DIR` 中 Unix socket 上的平等客戶端，該目錄模式為 0700，因此標準檔案權限即可進行存取控制，無需權杖。兩個客戶端都會按需啟動後端服務。CLI 即使沒有後端服務也能運作：它在程序內執行相同的服務（`--local`，或在無監聽時自動執行）。

2. 協定被寫了兩次。
   Rust IPC 類型、手寫的 `ipc.schema.json`（附有一個檢查兩者是否一致的測試），以及 idl 中獨立的客戶端都描述了相同的協定。

   Ferry：每個方法的參數和結果類型在 `lib/protocol` 中宣告一次。後端服務、程序內路徑和每個客戶端都透過這些類型進行編碼/解碼，而 `ferry schema` 會在編譯時從它們產生 JSON Schema。`protocol` 沒有依賴項，因此任何 Zig 工具（包括 idl）都可以直接匯入它。

3. 一個雜湊式的實用程式套件。
   `plume_utils` 包含裝置存取、簽署、來源、JIT、Tailscale、IPC、重新整理、微調和應用程式資料，並引入了 idevice、mdns-sd、xkit、reqwest、tailscale、goblin、image 和 zip。任何只需要裝置存取的工具（ios-webusb）都必須全部採用或重新實作它們。

   Ferry：每個關注點一個模組，且每個模組都在 `build.zig` 中命名其匯入項。`device`（libimobiledevice）無法看見 `signing`；`ipa` 無法看見 `device`；只有 `core` 看見一切。在其他地方使用 `device` 僅需額外負擔 `diag` + `plist` + libimobiledevice，而無其他更多。

4. 設定檔選擇分散在各層之間。
   plume 簽署器和 xkit 橋接器是兩個簽署路徑，而「單一設定檔」的後備機制必須在 `select_profile`（signer.rs）中重複一次，並在 `Device::install_app`（device.rs）中再次重複。

   Ferry：提供者只回答一個問題：「哪個憑證 + 設定檔 + 最終 bundle id？」（`provision.choose`，已進行單元測試）。簽署器僅負責簽署。安裝管線向提供者詢問一次並將答案傳遞下去。此步驟之後沒有任何東西會質疑它。

5. 業務邏輯位於 UI 中。
   `screen/mod.rs`（約 1.9k 行）和 `settings.rs`（約 1.7k 行）將流程控制與小部件混合在一起，而 `jimpactor-cli` 擁有相同流程的獨立副本。

   Ferry：流程位於 `core/pipeline.zig` 中，作為報告進度（檢查 → 設定檔 → 簽署 → 上傳 → 安裝）的有序步驟。GUI 和 CLI 僅呈現 `job.updated` 事件，因此兩者顯示相同的步驟和相同的錯誤文字。

6. 核心功能受特徵閥控管。
   `plume_core` 若沒有 `--features tweaks` 則無法編譯。

   Ferry：每個模組都能獨立建構和測試（`zig build test` 將每個模組的測試作為獨立的二進位檔執行）。GUI 是可選的（`-Dgui=false`）。

7. 長壽命的裝置工作執行緒具有脆弱的句柄。
   一個遺漏的 AFC `close()` 觸發了偵錯斷言並殺死了 Wi-Fi 工作執行緒。

   Ferry：每個裝置呼叫都會開啟其自己的 idevice/lockdown/service 句柄，並在每個路徑上使用 `defer` 釋放它們。沒有會卡住的每裝置工作執行緒存在。

## 模組圖形

```
diag ─┬─ plist ─┬─ ipa         libzip
      │         ├─ device      libimobiledevice (usbmuxd: USB + Wi-Fi)
      │         └─ provision   identities: files | exec plugin
      └─ signing               zsign (vendored C++, C ABI shim)
protocol                       wire types + schema, no deps
migrate = plist + provision + signing + device + ipa   (importers, e.g. Jimpactor)
core   = ipa + device + provision + signing + migrate + protocol
client = protocol

ferryd = core + protocol
ferry       = core + client + protocol + clap
ferry-gui = client + protocol + dvui (SDL3)
```

## 身分識別（憑證來源）

`<data>/identities/<name>/` 是以下其中之一：

- files：`*.p12` 加上可選的 `password` 檔案，以及一個或多個
  `*.mobileprovision`。涵蓋付費團隊以及從 Xcode、Jimpactor（`account export-p12`）或 AltServer 匯出的憑證。
- exec：`provider.json` = `{"exec": ["cmd", ...]}`。該命令將請求 `{"bundle_id", "udid", "ipa"}` 作為其最後一個參數，並輸出
  `{"p12", "password", "profile", "bundle_id"}`。從 Jimpactor 匯入的身分識別會搭配 `ferry provider jimpactor` 使用，這會快取設定檔並向 `jimpactor-cli` 請求新的設定檔（`lib/migrate`）。這是免費帳戶 Apple ID 設定的接縫：一個建立在現有 Rust
  xkit + omnisette crates 之上的輔助程式可以作為獨立程序插入此處，而無需將 HTTP/SRP/anisette 堆疊連結至後端。

設定檔選擇順序為：針對 bundle id 的精確設定檔；接著是
`<id>.<TEAMID>`（AltStore/SideStore/Jimpactor 免費帳戶慣例，
會重新識別應用程式）；然後是萬用字元。過期的設定檔以及不包含目標裝置的設定檔會被跳過，錯誤訊息會列出每個設定檔被拒絕的原因。

## 翻譯

`lib/i18n` 沒有相依性。它在建置時讀取嵌入的 gettext .mo 目錄，前端與 `core` 都透過它進行翻譯。

步驟名稱與工作狀態以英文鍵值（`inspect`、`sign`、`failed`）透過協議傳輸。每個客戶端會為顯示目的進行翻譯，因此不同語言的客戶端可以共用同一個後端。

工作標題與結果訊息由後端撰寫，使用啟動者的語言。

低層級程式庫診斷（`device`、`provision`、`signing`）保持英文。這些程式庫不依賴 `i18n`。

## 尚未建置

- Apple ID 登入 / 免費帳戶設定：一個包裝 xkit 的 exec provider。
- iOS 17+ RemotePairing / Tailscale / JIT。libimobiledevice 僅涵蓋透過 usbmuxd 的 lockdown。
- 自動重新整理排程（後端是自然的家：一個排隊 `install` 工作的計時器）。
- 來源、tweak 注入 UI（`signing.Options.inject` 已經將 dylibs 傳遞給 zsign）、應用程式資料備份。
