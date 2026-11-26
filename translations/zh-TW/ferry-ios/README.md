# Ferry for iOS

在裝置上為 iPhone 和 iPad 進行側載，採用 SwiftUI。它是 [Ferry](../ferry)（Linux）的 iOS 兄弟版本，涵蓋了 SideStore 的功能，無需 JIT 且提供更原生的介面：

- 使用任何 Apple ID 登入（支援雙重驗證、免費或付費團隊）；憑證、App ID 和裝置註冊均由系統自動處理。
- 從「檔案」、Safari、AirDrop 或來源安裝 `.ipa` 檔案；在過期前重新整理，並在前一天收到提醒。
- 來源：AltStore 格式的儲存庫（v1 和 v2 版面配置）以及 GitHub 儲存庫，其發布版本的 `.ipa` 資產即為版本。
- 權限：查看 IPA 中的每個二進位檔請求了哪些權限、免費 Apple ID 無法獲得哪些權限、來源宣告了哪些，以及之後配置文件實際授予了哪些權限。
- 微調：注入 `.dylib` 和 `.framework`、移除連結的函式庫、重新命名、變更 bundle id、版本或最低 iOS 版本、移除擴展、啟用「檔案」共用。

## 如何在沒有電腦或 JIT 的情況下運作

迴路 VPN（LocalDevVPN 或 StosVPN）將 `10.7.0.1` 路由至手機本身的 `lockdownd`。透過手機的配對文件，Ferry 像電腦一樣與之通訊：使用 AFC 上傳、`installation_proxy` 安裝。沒有程式在偵錯器中執行，因此不需要 JIT。

## 版面配置

```
core/      Rust 靜態函式庫：登入、供應、簽署、注入、安裝
App/       SwiftUI 應用程式（Core 橋接、模型、檢視）
idlproj.yml
```

請參閱 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 建置（Linux）

需要 `xtool setup`（Darwin SDK）、swiftly 的 Swift 工具鏈、`rustup target add aarch64-apple-ios`，以及 [idl](../idl)。

```sh
core/build-ios.sh            # core/out/libferry_core.a + ferry_core.h
idl build -c release         # build/release/Ferry.ipa（ad-hoc 簽署）
idl test -c release          # bundle 檢查
cargo test --manifest-path core/Cargo.toml
cargo run --manifest-path core/Cargo.toml --example smoke -- App.ipa [tweak.dylib]
```

IPA 必須重新簽署才能安裝（例如透過 Jimpactor 或桌面版 Ferry 執行 `idl install <udid> Ferry`）。之後，一旦你將它的 IPA 加入程式庫，Ferry 就會像其他應用程式一樣自行重新整理。

在裝置上，anisette 需要僅解譯器（TCI）的 Unicorn for iOS：使用 `bash ~/projs/WaffleStore/AnisetteKit/MacADI/build-ios.sh` 建置它，或將 `UNICORN_IOS_DIR` 指向你自己的建置版本。
