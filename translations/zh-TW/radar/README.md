# radar

給代理程式的報告。每份報告都指向 pull 工作區中的某一行程式碼，並記錄儲存庫、檔案、行號、該行的文字、可選的備註，以及提交時間。CLI 是無狀態的：每次執行都會開啟位於 `<workspace>/issues/radar.db` 的 PoloDB 資料庫，完成工作後即結束。

```sh
radar add pull src/main.rs 42 --note "panics on an empty pullfile"   # the line text is read from the file
radar list [--all] [--json]
radar close 3 / radar reopen 3 / radar rm 3
radar export        # issues/docs/NNNN.md per open report + issues/docs/index.md
radar mcp [--root DIR]   # MCP server (stdio): add/list/close/reopen/rm/export
```

工作區根目錄為 `$PULL_ROOT`，否則是目前目錄上層最近、含有 `pullfile.plist` 的目錄。

同一時間只有一個處理程序能開啟 `radar.db`，因此每個指令都只為單一操作開啟它，
若另一個處理程序正在使用，則會稍待片刻。這也包括 `radar mcp`，
它會在每次工具呼叫時才開啟，所以代理程式連線期間 CLI 仍可正常運作。
pullfile 的 `mcp_servers` 區段會將 `radar mcp` 與 `pull mcp` 一起註冊到
讀取 `pull mcp-servers` 的編輯器與代理程式中，例如 ycode-pull。

- **Pull：**precommit hook 會執行 `radar export` 並暫存 `issues/radar.db`。`issues/docs` 已被 gitignore，由 wiki 發布於 `issues` 之下。
- **Wiki：**在文件頁面上選取文字並按右鍵。「Add to Radar」選單會複製對應的 `radar add …` 指令，其中的儲存庫、檔案、原始碼行與你的選取內容都已填好。
