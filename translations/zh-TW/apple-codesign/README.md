# apple-codesign

`apple-codesign` 是一個 crate，實作與 Apple 平台上的程式碼簽署
相關的功能。

所有功能皆以純 Rust 實作，不需要任何第三方
或專有軟體，也不需要在 Apple 平台上執行。

我們相信此 crate 提供了 Apple 官方工具之外
最完整的 Apple 程式碼簽署實作。我們支援下列
功能：

* 簽署 Mach-O 二進位檔（Apple 作業系統上的可執行檔格式）。
* 簽署、公證並裝訂目錄 bundle（例如 `.app` 目錄）。
* 簽署、公證並裝訂 XAR 封存檔 / `.pkg` 安裝程式。
* 簽署、公證並裝訂 DMG 磁碟映像檔。

這一切意味著，只要能編譯這個 Rust crate，你就能在任何地方
簽署、公證並發佈 Apple 軟體。官方支援 Linux、Windows 和 macOS，
其他作業系統（如 BSD）也應該可以運作。

更多資訊請參閱 https://docs.rs/apple-codesign/latest/apple_codesign/ 的 crate 文件，
以及 https://gregoryszorc.com/docs/apple-codesign/main/ 的
終端使用者文件。

# `rcodesign` CLI

此 crate 定義了一個 `rcodesign` 執行檔，提供 CLI 介面來使用
此 crate 的部分功能。安裝方式：

```bash
# From a Git checkout
$ cargo run --bin rcodesign -- --help
$ cargo install --bin rcodesign

# Remote install.
$ cargo install --git https://github.com/indygreg/apple-platform-rs --branch main --bin rcodesign apple-codesign
```
