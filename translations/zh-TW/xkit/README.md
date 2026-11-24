# XKit for Rust

`xkit` 是一個用於 Apple 開發者驗證、佈建、
程式碼簽署與安裝的函式庫。它在 Windows、macOS
和 Linux 上使用原生 Rust 函式庫。這是 [xtool-org/xtool](https://github.com/xtool-org/xtool)
中 XKit 的 Rust 移植版，原作者為
Kabir Oberai。應用程式與
CLI 可以另外採用這個 crate。

| Swift 領域 | Rust API |
| --- | --- |
| GrandSlam / Anisette | `grand_slam::AnisetteDataProvider` 與 Xcode GrandSlam 常數；登入與 anisette 產生由呼叫端提供 |
| HTTPClientProtocol | `http::HTTPClientProtocol`、`HTTPClient`，可注入的請求/回應；anisette websocket 佈建仍留在 `omnisette` |
| DeveloperServices / OpenAPI | 用於舊版 plist 的 `DeveloperServicesClient`；用於 JSON:API、Xcode 驗證或 ASC ES256 JWT、分頁與結構化錯誤的 `DeveloperAPIClient` |
| 佈建操作 | `register_device`、`fetch_certificate`、`upsert_app`、`assign_app_groups`、`fetch_profile`、`DeveloperServicesProvisioningOperation` |
| 模型 / Entitlements | `Certificate`、`Keypair`、`PrivateKey`、`Mobileprovision`、具型別的 `Entitlement` 與無損的 `Entitlements` |
| 簽署器 | `SigningContext`、`Signer`、`AutoSigner`；原生 `apple-codesign`，包含獨立的擴充功能 entitlements |
| 安裝 | `Connection`、`ClientDevice`、`IPAUploader`、`IPAInstaller`、`AppInstaller`、`ProfileManager`、`HeartbeatHandler`、`Debugger` |
| 整合 | `IntegratedInstaller`、`IntegratedInstallerDelegate`；解開封裝 → 準備裝置 → 佈建 → 簽署 → 封裝 → 安裝 |
| 公用程式 | `ProvisioningIdentifiers`、記憶體/目錄儲存、Apple `KeychainStorage`、`KeyValueSigningInfoManager`、`ZIPCompressor` |

Rust 的 future、所有權與 `tokio::time::sleep` 取代了 Swift 的工作與 C
生命週期輔助工具。自訂連線查詢使用傳給
`Connection::with_provider` 的 `IdeviceProvider`。探索會傳回裝置變更快照的非同步串流。
捨棄探索串流會使其停止；捨棄 heartbeat 會停止其
工作。AFC 上傳以 1 MiB 區塊串流進行，並在完成、
失敗或取消時清理暫存檔案。設定檔列舉支援 iOS 9.3 之前的協定。
上游的 DDI 掛載器已停用，沒有可移植的作用中 API。

## 簽署應用程式

```rust,no_run
use std::{path::Path, sync::Arc};
use xkit::{ASCKey, AutoSigner, DeveloperAPIAuthData, DeveloperAPIClient, SigningContext};
use xkit::utilities::{DirectoryStorage, KeyValueSigningInfoManager, persistent_directory};

async fn sign(app: &Path, key: ASCKey) -> xkit::Result<String> {
    let client = DeveloperAPIClient::new(DeveloperAPIAuthData::AppStoreConnect(key), None)?;
    let manager = Arc::new(KeyValueSigningInfoManager {
        storage: Arc::new(DirectoryStorage::new(persistent_directory()?)),
    });
    let signer = AutoSigner { context: SigningContext::new(client, manager) };
    signer.sign(
        app,
        &|_certificates| Box::pin(async { false }),
        &|stage| println!("{stage}"),
        &|_progress| {},
        &|| Ok(()),
    ).await
}
```

若使用 Xcode 驗證，請傳入 `DeveloperServicesLoginToken`（ADSID、Xcode
GrandSlam 權杖、到期時間）以及能提供最新 anisette
標頭的 `AnisetteDataProvider`：`DeveloperAPIClient::new(DeveloperAPIAuthData::Xcode(XcodeAuthData {
login_token, team_id }), Some(provider))`。xkit 本身不執行 GrandSlam
登入；Jimpactor 的 `plume_utils::xkit_auth` 是其中一種實作。

`SigningContext::target_device` 可在佈建前選擇性地註冊裝置。
安裝 IPA 或應用程式時，`IntegratedInstaller` 會自動提供它。
`AutoSigner` 就地簽署；`IntegratedInstaller::install` 則在暫時的
暫存目錄中運作。整合委派物件控制憑證撤銷，
並接收配對/解鎖訊息以及階段/進度更新。預設委派物件的
撤銷政策與 Swift 一致（接受）；可覆寫它以顯示確認畫面。

目錄儲存會把私密金鑰以檔案形式保存；呼叫端也可以改選
Apple 鑰匙圈儲存或其他 `KeyValueStorage`。預設的
`KeyValueSigningInfoManager` 把資料儲存在記憶體中。憑證序號以
數值比較，因此 Apple API 傳回的前導零不一致不會妨礙重複使用。
未知的 entitlement 鍵會在一般更新中保留；免費團隊的篩選會移除
未知與付費的 entitlements，與來源政策一致。CSR 使用 RSA-2048 搭配
SHA-256，與此儲存庫現有的 Rust 憑證實作一致。

## 驗證

```text
cargo check -p xkit
cargo test -p xkit
cargo clippy -p xkit --all-targets --no-deps -- -D warnings
cargo fmt -p xkit --check
```

測試以離線方式執行，使用注入的 HTTP 回應、產生的測試憑證，
以及獨立的 ARM64 Mach-O 測試資料。測試涵蓋請求轉換、
JWT 簽章/更新、分頁、entitlement 改寫、憑證重複使用與
撤銷取消、設定檔建立、ZIP 往返、獨立的擴充功能
entitlements，以及完整的佈建/簽署流程。測試資料的原始碼與
LLVM 重新產生指令位於 `tests/fixtures/minimal.c`。

即時的 Apple 驗證、USB/網路裝置、原生 Apple 鑰匙圈，以及
安裝，都需要以對應的帳號/硬體/平台來驗證。
測試套件不會存取任何實際帳號或裝置。

## 出處與授權

**XKit: Copyright © 2019 Kabir Oberai. All rights reserved.**
個別的原始碼檔案也帶有標註 2020 與 2021 年的著作權聲明。

XKit 是 [XTool](https://github.com/xtool-org/xtool) 的一部分，後者以 **MIT 授權**散布。
XTool 的 MIT 授權聲明為
Copyright (c) 2024 Kabir Oberai.

原本的 Swift 檔案已被移除。
XTool 的 MIT 聲明保留在 [LICENSE](LICENSE) 中。
