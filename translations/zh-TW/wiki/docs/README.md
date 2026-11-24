# 概覽

`wiki` 會把 [pull](https://github.com/jbisfun/pull) 工作區中的每個儲存庫轉換成一個靜態網站，發佈於 <https://jbisfun.github.io>。每個儲存庫會得到：

- 以其 `README.md` 作為入口頁面（`<repo>/index.html`），
- 其 `docs/` 資料夾中的頁面（`<repo>/docs/...`），
- 由該語言自己的工具產生的程式碼參考（`<repo>/api/...`）。

## 運作方式

`wiki build`（一個 Rust 執行檔，`src/`）會執行下列步驟：

1. **收集**（`collect.rs`）：執行 `pull status --json`，保留每個已複製的儲存庫，連同其 README、GitHub URL（來自 `origin` 遠端）以及 `wiki.toml` 中對應的表格。
2. **程式碼參考**（`apidoc.rs`），輸出到 `.build/api/<repo>/<tool>/`：
   - Rust：當儲存庫有 `Cargo.toml` 時執行 `cargo doc --no-deps`（rustdoc），並使用該儲存庫自己的 target 目錄。
   - Lua：對受追蹤的 `*.lua` 檔案使用 [LDoc](https://github.com/lunarmodules/ldoc)（`apt install lua-ldoc`），但 `*.x.lua` 掛鉤指令碼除外。只會讀取 `---` 文件註解（檔案第一個註解上用 `-- @module name`）。
   - JavaScript：對有 `package.json` 且含 `/** */` 註解的儲存庫，針對受追蹤的 `*.js`/`*.mjs` 使用 [JSDoc](https://jsdoc.app)（wiki 的開發相依套件）。
   缺少工具或執行失敗只會發出警告，因此網站仍可建置。
3. **資產**（`bundle.rs`）：內嵌的 [rolldown](https://rolldown.rs) 會連同 npm 匯入項目（Bootstrap 的 collapse 與 dropdown、clipboard.js）一起打包並壓縮 `assets/main.js`。[lightningcss](https://lightningcss.dev) 會把 `assets/style.css` 與 Bootstrap 的 CSS 打包在一起，再加上 syntect 根據其淺色與深色主題產生的程式碼醒目提示 CSS。輸出放在 `dist/_assets`。
4. **渲染**（`render.rs`）到 `dist/<repo>/...`。mdBook 專案（有 `docs/book.toml`）會使用該書的 `src` 資料夾，並以其 `SUMMARY.md` 作為文件側邊欄。
   - `*.md` 使用 [comrak](https://github.com/kivikakk/comrak)：GFM 表格與自動連結、智慧標點、`{#id}` 標題屬性，以及在建置時由 syntect 進行的醒目提示。每個區塊都帶有 `data-sourcepos`，因此 Radar 可以把選取範圍對應回原始碼行。
   - `*.jinja` 使用 [minijinja](https://github.com/mitsuhiko/minijinja)。請參閱[範本](templating.jinja)。
   - `docs/` 中的其他所有檔案都會當作資產複製。
   - 連結會依儲存庫解析，因此 README 中連結到 `docs/setup.md` 時，會導向渲染後的頁面。連結到其他儲存庫檔案時會前往 GitHub（圖片則前往其原始 URL）。連結是用 lol_html 改寫的，因此原始 HTML 中的連結也涵蓋在內。
5. **語言**（`i18n.rs`、`translate.rs`）：第 4 步會針對 `wiki.toml` `[i18n]` 中的每個語言各執行一次；請見[語言](#languages)。
6. **發佈**（`wiki publish`）：以 rsync 將 `dist/` 鏡像到 `jbisfun.github.io` 儲存庫並加入暫存。

## 哪些內容會重新產生

輸入是以 git 識別它們的方式來識別（`state.rs`），而 `.build/state.json` 會保存每個部分上次建置時使用的鍵：

| 部分 | 下列項目變更時重新建置 |
| - | - |
| 儲存庫的程式碼參考 | 該儲存庫的 HEAD tree id、其未提交變更的 patch id，或其 `wiki.toml` 設定 |
| 儲存庫的頁面 | 其任何頁面來源的 blob id、其程式碼參考的鍵，或全域鍵 |
| 儲存庫在其他語言的頁面 | 同上，再加上其翻譯與翻譯後的字串 |
| 全部 | 全域鍵：`templates/` 與 `locales/` 的 blob id、語言清單、導覽列中的儲存庫清單、網站標題，或 `wiki` 執行檔 |
| `dist/_assets` | `assets/`、`pnpm-lock.yaml` 的 blob id，或 `wiki` 執行檔 |

`.jinja` 頁面與首頁可以顯示網站的任何資訊，因此每次建置都會渲染。`wiki build --force`（`just rebuild`）會忽略狀態。

## wiki.toml

各儲存庫的設定，以 pull 儲存庫名稱為鍵；全部皆為選用。完整清單位於 [wiki.toml](../wiki.toml) 的開頭。

```toml
[repos.launchd]
skip = true                            # leave the repo out

[repos.ycode]
category = "ycode"                     # header dropdown and home page section (default: the pull group, else "Other")
description = "A Zed fork you can script in Lua."   # home page blurb (default: the README's first sentence)
rust = { packages = ["lua_hooks"] }    # cargo doc -p ... (default: default-members)

# lua = { files = ["lib"] }  /  js = { files = ["src"] }  /  rust = false
```

位於 pull 群組中的儲存庫（`fossify-ios/notes-ios`）會以其自己的名稱（`notes-ios`）列在該群組的類別之下。過長的 README 句子在首頁會於第一個逗號處截斷。

## 語言

英文是來源語言，位於網站根目錄。`[i18n] locales` 中的每個語言（目前是 `zh-TW`）都是整個網站的完整副本，放在其小寫標籤之下（`/zh-tw/...`），頁首有語言選單，各副本之間以 `hreflang` 連結。程式碼參考維持英文並共用。

- **介面**（導覽列、側邊欄、頁尾、首頁）：`locales/<tag>/main.ftl` 中的 [Fluent](https://projectfluent.org) 訊息，透過 fluent-templates 載入。範本呼叫 `t('key', name=value)`。新增語言需要一個 `locales/<tag>/main.ftl`，包含 `locales/en/main.ftl` 中的每個鍵。
- **頁面**（README、`docs/`）以及 `wiki.toml` 的描述與分類，會透過任何相容 OpenAI 的聊天 API 機器翻譯（`[i18n.translator]`：`base_url`、`model`、`api_key_env`、`reasoning_effort`、`jobs`、`chunk`；預設為本機 Ollama），使用 async-openai。頁面依其 markdown 結構切成最多 `chunk` 個字元的區塊（text-splitter）；提示詞要求程式碼、連結、HTML 與範本標籤保持原樣。
- **快取**：`translations/<tag>/<repo>/<path>`，加上 `sources.json`（頁面 -> 其翻譯所根據的英文 blob id）與 `strings.json`，與 wiki 一起提交。只有當頁面的英文 blob id 改變時，才會再送去翻譯；在那之前會顯示舊的翻譯（並在建置記錄中發出警告）。已刪除頁面的翻譯會被清除。
- `WIKI_TRANSLATE=0`，或無法連線到翻譯服務時，只從快取建置：沒有翻譯的頁面會以英文顯示並附上提示。翻譯後的頁面會附上「機器翻譯」提示並連結英文原文，Radar 只在英文頁面上提供。
- 在儲存庫的設定表中使用 `translate = false` 或 `translate = { files = ["README.md"] }` 可限制翻譯範圍（ycode 的上游 Zed 文件與 `issues` 中的 radar 回報維持英文）。

## 指令

```sh
just build     # pnpm install, then wiki build into dist/
just rebuild   # the same, ignoring .build/state.json
just publish   # build, then copy into ../jbisfun.github.io and git add
just serve     # build and serve dist/ on http://localhost:8000
just clean
```

環境變數：`PULL_ROOT`（工作區根目錄，預設為 `..`）、`WIKI_SKIP`（以逗號分隔、要排除的儲存庫，疊加在 `wiki.toml` 的 `skip` 之上）、`WIKI_TITLE`、`WIKI_PUBLISH_DIR`、`WIKI_TRANSLATE=0`（不呼叫翻譯服務），以及 `[i18n.translator] api_key_env` 所指定的變數。

## pull 掛鉤

工作區的 `pullfile.plist` 會在 `precommit` 掛鉤中執行 `just publish`，因此 `pull commit` 會把重新產生的網站放進同一個提交的 `jbisfun.github.io` 中，而 `pull push` 則會將它部署到 GitHub Pages。

撰寫頁面請參閱[範本](templating.jinja)。
