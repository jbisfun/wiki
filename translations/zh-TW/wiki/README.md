# wiki

由 [pull](https://github.com/jbisfun/pull) 工作區中的每個儲存庫建置而成的靜態網站，發佈於 <https://jbisfun.github.io>：每個儲存庫的 README 是其入口頁面，旁邊是它的 `docs/` 資料夾，以及由 rustdoc、LDoc 和 JSDoc 產生的程式碼參考。

這是一個 Rust 執行檔：以 comrak 處理 markdown，使用 minijinja（Jinja2）範本，並內嵌 rolldown 來打包用戶端 JS（Bootstrap、clipboard.js）。由 Git 物件 ID 決定哪些內容需要重新產生。各儲存庫的設定位於 [wiki.toml](wiki.toml)。本網站也以繁體中文發佈於 `/zh-tw/` 之下：介面字串使用 Fluent，頁面則經機器翻譯並快取於 `translations/`。

```sh
just build     # dist/
just publish   # stage into ../jbisfun.github.io
```

文件：[docs/README.md](docs/README.md)、[範本](docs/templating.jinja)。
