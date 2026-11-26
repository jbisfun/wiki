# 概覽

`wiki` 會將 [pull](https://github.com/jbisfun/pull) 工作區中的每個儲存庫轉換為單一靜態網站，並發布至 <https://jbisfun.github.io>。每個儲存庫都會獲得：

- 其 `README.md` 作為首頁（`<repo>/index.html`），
- 其 `docs/` 資料夾中的頁面（`<repo>/docs/...`），
- 由該語言自有工具產生的程式碼參考文件（`<repo>/api/...`）。

## 運作方式

`wiki build`（一個 Rust 二進位檔案，位於 `src/`）會執行以下步驟：

1. **收集**（`collect.rs`）：執行 `pull status --json` 並保留每個已複製的儲存庫，包含其 README、GitHub URL（來自 `origin` 遠端）以及 `wiki.toml` 中的表格。
2. **程式碼參考文件**（`apidoc.rs`），輸出至 `.build/api/<repo>/<tool>/`：
   - Rust：當儲存庫含有 `Cargo.toml` 時，使用 `cargo doc --no-deps`（rustdoc），並採用該儲存庫自己的目標目錄。
   - Lua：[LDoc](https://github.com/lunarmodules/ldoc)（`apt install lua-ldoc`）處理受追蹤的 `*.lua` 檔案，排除 `*.x.lua` 鉤腳本。僅擷取 `---` 文件註解（檔案第一個註解上的 `-- @module name`）。
   - JavaScript：[JSDoc](https://jsdoc.app)（wiki 開發依賴套件）處理含有 `package.json` 且包含 `/** */` 註解的受追蹤 `*.js`/`*.mjs` 檔案。
   缺少工具或執行失敗僅發出警告，因此網站仍可正常建置。
3. **資產**（`bundle.rs`）：內嵌的 [rolldown](https://rolldown.rs) 會捆綁並壓縮 `assets/main.js` 及其 npm 依賴項（Bootstrap 的折疊與下拉選單、clipboard.js）。[lightningcss](https://lightningcss.dev) 會捆綁 `assets/style.css`，包含 Bootstrap 的 CSS，以及由 syntect 從其淺色和深色主題產生的程式碼語法高亮 CSS。輸出結果位於 `dist/_assets`。
4. **渲染**（`render.rs`）至 `dist/<repo>/...`。mdBook 專案（含有 `docs/book.toml`）會使用該書的 `src` 資料夾及其 `SUMMARY.md` 作為文件側邊欄。
   - `*.md` 使用 [comrak](https://github.com/kivikakk/comrak)：支援 GFM 表格和自動連結、智慧標點符號、`{#id}` 標題屬性，以及建置時由 syntect 產生的語法高亮。每個區塊都帶有 `data-sourcepos`，因此 Radar 可以將選取範圍對應回其原始行數。
   - `*.jinja` 使用 [minijinja](https://github.com/mitsuhiko/minijinja)。請參閱 [模板](templating.jinja)。
   - `docs/` 中的其他每個檔案都會作為資產複製。
   - 連結會相對於儲存庫解析，因此 README 中連結至 `docs/setup.md` 的項目會導向已渲染的頁面。連結至其他儲存庫檔案的項目會導向 GitHub（圖片則導向其原始 URL）。連結會使用 lol_html 進行重寫，因此原始 HTML 中的連結也會一併處理。
5. **語言**（`i18n.rs`、`translate.rs`）：步驟 4 會針對 `wiki.toml` `[i18n]` 中的每種語言執行一次；請參閱 [語言](#languages)。
6. **發布**（`wiki publish`）：使用 rsync 將 `dist/` 鏡像至 `jbisfun.github.io` 儲存庫並暫存。

## 哪些項目會重新生成

輸入內容的識別方式與 git 相同（`state.rs`），而 `.build/state.json` 會保留每個組件上次建置時使用的金鑰：

| 組件 | 變更時重新建置 |
| - | - |
| 儲存庫的程式碼參考文件 | 儲存庫的 HEAD 樹狀結構 ID、未提交變更的 patch ID，或其 `wiki.toml` 設定 |
| 儲存庫的頁面 | 任何頁面來源的 blob ID、其程式碼參考金鑰，或全域金鑰 |
| 另一種語言中的儲存庫頁面 | 同上，加上其翻譯和已翻譯的字串 |
| 所有內容 | 全域金鑰：`templates/` 和 `locales/` 的 blob ID、語系清單、導覽列中的儲存庫清單、網站標題，或 `wiki` 二進位檔案 |
| `dist/_assets` | `assets/`、`pnpm-lock.yaml` 或 `wiki` 二進位檔案的 blob ID |

`.jinja` 頁面和首頁可以顯示關於網站的任何資訊，因此它們會在每次建置時渲染。`wiki build --force`（`just rebuild`）會忽略狀態。

## wiki.toml

每個儲存庫的設定，以拉取儲存庫名稱作為索引鍵；所有選項皆為可選。完整列表位於 [wiki.toml](../wiki.toml) 頂部。

```toml
[repos.launchd]
skip = true                            # 將該儲存庫排除在外

[repos.ycode]
title = "ycode"                       # 顯示名稱（預設：儲存庫名稱，不含其拉取群組）
category = "ycode"                     # 標題下拉選單與首頁區塊（預設：拉取群組，否則為「Other」）
description = "A Zed fork you can script in Lua."   # 首頁簡述（預設：README 的第一句話）
rust = { packages = ["lua_hooks"] }    # cargo doc -p ...（預設：default-members）

# lua = { files = ["lib"] }  /  js = { files = ["src"] }  /  rust = false
```

位於拉取群組內的儲存庫（`fossify-ios/notes-ios`）會以其自身名稱（`notes-ios`）列於該群組的分類下，除非它們設定了 `title`/`category`。長 README 句子會在其第一個逗號處截斷以用於首頁。

## 語言

英文是原始語言，位於網站根目錄。`[i18n] locales`（目前為 `zh-TW`）中的每個區域設定都是其小寫標籤下的完整網站副本（`/zh-tw/...`），標頭中包含語言選單，且各副本之間有 `hreflang` 連結。程式碼參考保持英文並共用。

- **Chrome**（導航列、側邊欄、頁尾、首頁）：`locales/<tag>/main.ftl` 中的 [Fluent](https://projectfluent.org) 訊息，使用 fluent-templates 載入。模板呼叫 `t('key', name=value)`。新的區域設定需要一個 `locales/<tag>/main.ftl`，其中包含 `locales/en/main.ftl` 中的所有索引鍵。
- **頁面**（READMEs、`docs/`）以及 `wiki.toml` 的描述與分類會透過任何 OpenAI 相容的聊天 API（`[i18n.translator]`：`base_url`、`model`、`api_key_env`、`reasoning_effort`、`jobs`、`chunk`；預設為本機 Ollama）進行機器翻譯，使用 async-openai。頁面會沿著其 markdown 結構（text-splitter）分割成最多 `chunk` 個字元的區塊；提示詞會保持程式碼、連結、HTML 和模板標籤不變。
- **快取**：`translations/<tag>/<repo>/<path>` 加上 `sources.json`（頁面 -> 其來源英文的 blob id）與 `strings.json`，隨 wiki 一起提交。僅當頁面的英文 blob id 變更時，才會送回翻譯器；在此之前會顯示舊翻譯（在建置記錄中帶有警告）。已刪除頁面的翻譯會被修剪。
- `WIKI_TRANSLATE=0`，或無法連線的翻譯器，會單獨從快取建置：沒有翻譯的頁面會以英文顯示並附帶通知。已翻譯的頁面帶有「機器翻譯」通知，連結至英文原文，且 Radar 僅支援英文。
- 儲存庫表格中的 `translate = false` 或 `translate = { files = ["README.md"] }` 限制翻譯範圍（ycode 的上游 Zed 文件與 `issues` 中的雷達報告保持英文）。

## 命令

```sh
just build     # pnpm install，然後將 wiki 建置至 dist/
just rebuild   # 相同操作，忽略 .build/state.json
just publish   # 建置，然後複製到 ../jbisfun.github.io 並 git add
just serve     # 建置並在 http://localhost:8000 上提供 dist/
just clean
```

環境變數：`PULL_ROOT`（工作區根目錄，預設 `..`）、`WIKI_SKIP`（要排除的儲存庫，以逗號分隔，位於 `wiki.toml` 中的 `skip` 之上）、`WIKI_TITLE`、`WIKI_PUBLISH_DIR`、`WIKI_TRANSLATE=0`（不呼叫翻譯器），以及由 `[i18n.translator] api_key_env` 命名的變數。

## pull hook

工作區的 `pullfile.plist` 將 `just publish` 作為 `precommit` hook 執行，因此 `pull commit` 會在同一個提交中將重新產生的網站落地至 `jbisfun.github.io`，而 `pull push` 則將其部署至 GitHub Pages。

請參閱 [Templating](templating.jinja) 以撰寫頁面。
