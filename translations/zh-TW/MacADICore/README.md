MacADICore
==========

Swift 套件：`.package(url: "https://github.com/jbisfun/MacADICore", branch: "main")`，
產品 `MacADICore`（二進位目標 `MacADICore.xcframework`；需連結 libz 與 libbz2）。

`src/{lib,adi,vm,macho,capi}.rs` 內建自 sacca97/os-findmy-e
的提交 374d83854f657a7fdca45f813387d99d491db0e2，如同 Jimpactor 的 `crates/omnisette/src/mac_anisette.rs`
所使用的版本。此程式碼採 MIT 授權
（請參閱 LICENSE）。它在 Unicorn 下模擬固定版本的 x86_64 Mac CoreADI，
並公開原始的 C ABI。它不包含 Apple 的 CoreADI 二進位檔。

[AppStoreAuth](https://github.com/jbisfun/AppStoreAuth) 的 `MacAnisetteKit` 移植了 Jimpactor 的 `mac_libraries.rs`
（以範圍請求取得並驗證 iTunes 12.8.3 的 CoreADI）與 `mac_anisette.rs`
（保存身分/儲存區、GrandSlam 機器佈建、全新的 MID/OTP）。
使用者的 Apple 帳號資料不在 CoreADI 儲存區中。

`MacADICore.xcframework` 是靜態的 arm64 iOS 裝置框架。
它包含內建的 Rust 實作，以及 mahee96/unicorn 的 x86 客體
引擎，並以 Tiny Code Interpreter 建置（無 JIT）。可在
此 Linux 主機上以 `build-ios.sh` 從原始碼重新建置。建置指令碼會下載
固定版本的 Unicorn 分支；不會下載 Apple 的 CoreADI 二進位檔。應用程式
會在首次執行時自行取得 CoreADI，並檢查承載與二進位檔的 SHA-256。
建置目標僅限 arm64 iOS 裝置；不支援模擬器。

機器 anisette 不是 Store SAP 動作簽章。`MacAnisetteKit`
提供 X-Apple-I-MD/-M；App Store 原生登入還需要另外
經 SAP 簽署的請求本文。Jimpactor 的 mac_anisette.rs 並未實作 SAP。
對於未簽署的 Store 驗證請求，Apple 仍可能傳回 HTTP 204。Store 專用的
SP 佈建與 FairPlay keybag 處理在此也尚未實作。

在 Linux 上的冒煙測試（在 `cargo build --release` 之後，搭配本機的 Unicorn
封存檔，以及另行取得並經雜湊檢查的 CoreADI 映像檔）：

    cc -I include tests/smoke.c target/release/libmac_adi_ios.a \
      /path/to/linux/libunicorn.a -ldl -lpthread -lm -o smoke
    ./smoke /path/to/CoreADI-x86_64

全新機器的預期結果：`adi_headers(-2): -2 (machine is not provisioned)`。
此測試不會發出網路呼叫或佈建請求。

佈建必須在 `adi_provisioning_finish` 之後捨棄 `STORE_DIR/adi.pb`：
該舊版的整機 blob 會遮蔽新的每使用者儲存區，否則即使 Apple 已接受
佈建交換，`adi_headers(-2)` 仍會立即傳回 `-2`。C ABI 會在 Swift 層
匯出並儲存該儲存區之前執行這個步驟（與 Jimpactor 的 mac_anisette.rs 一致）。
