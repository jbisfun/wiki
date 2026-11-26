# wiki

由 [pull](https://github.com/jbisfun/pull) 工作區中的所有儲存庫所建構的靜態網站，發佈至 <https://jbisfun.github.io>：每個儲存庫的 `README` 即為其入口頁面，旁邊並列有 `docs/` 資料夾以及由 rustdoc、LDoc 和 JSDoc 產生的程式碼參考文件。

這是一個 Rust 二進位檔案：使用 comrak 處理 Markdown、minijinja（Jinja2）模板，以及內建的 rolldown 來捆綁客戶端 JS（Bootstrap、clipboard.js）。Git 物件 ID 決定哪些內容需要重新產生。每個儲存庫的設定位於 [wiki.toml](wiki.toml)。該網站也提供繁體中文版本，位於 `/zh-tw/`：Chrome 使用的 Fluent 字串與機器翻譯頁面快取在 `translations/` 中。

```sh
just build     # dist/
just publish   # 部署至 ../jbisfun.github.io
```

文件：[docs/README.md](docs/README.md)、[模板語法](docs/templating.jinja)。


已發佈的網站採用 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 授權。與 Apple Inc. 無隸屬關係。
