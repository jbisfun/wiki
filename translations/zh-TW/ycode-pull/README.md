# ycode-pull

在 ycode 中使用 [pull](https://github.com/jbisfun/pull)，是建立在
ycode 的 `lua_hooks`（`gpui.open_window`）上的 Lua 擴充功能。

一個視窗，提供 status / sync / update / push、一個 commit 輸入框（40 字元計數器、`-a` 切換、
ctrl-enter 會透過 `pull commit` 提交，因此 pullfile 的 lint 規則與 hooks 都會套用），
以及工作區 worktree。指令在背景執行，並即時串流其輸出。

## 安裝

    # from the ycode-pull clone
    ln -s "$PWD" ~/.config/zed/hooks/ycode-pull

然後執行「ycode: reload hooks」。以下列方式開啟它

    ycode.dispatch("pull::Open")                       -- executor
    "ctrl-alt-p": ["ycode::Run", { "name": "pull::Open" }]   -- keymap.json

工作區根目錄為 `$PULL_ROOT`（由 `pull shell` / `pull env` 設定），否則是 ycode 中已開啟資料夾
上層最近的 `pullfile.plist`（優先使用作用中的視窗），再不然是 ycode 工作目錄上層的；
也可以在視窗中變更。`pull` 必須位於 ycode 的 PATH 上。

## 變更面板

「pull: changes」會切換左側停駐面板，顯示每個儲存庫的變更、分支與 ahead/behind。

- 點擊檔案即可開啟；勾選檔案（或儲存庫）即可透過 `pull add` / `pull unstage` 暫存。
- Commit 會執行 `pull commit`（若沒有暫存任何內容則加上 `-a`），並套用 pullfile 的 lint 與 hooks。
- Sync、Update 與 Push 作用於整個工作區。Zed 的 git 面板會被隱藏。

## 工作面板

「pull: jobs」會切換底部停駐面板，顯示 pullfile 的 `jobs` 與臨時 session。檢視器會即時顯示所選的終端機：

- 可在其中輸入、傳送 ctrl-c、啟動／停止／重新啟動、載入或卸載工作、移除 session
- 在 `$TERMINAL` 中開啟它（透過 `pull session attach`）

## MCP

在 pull 工作區中，外掛會執行 `pull mcp-servers`，並註冊它傳回的每個伺服器
（`context_servers`，記憶體內的設定層）：包括 `pull mcp --root <root>` 本身
（工作區、搜尋、exec 與終端機 session 工具），以及 pullfile 的
`mcp_servers` 區段所設定的其他伺服器，例如

    <key>mcp_servers</key>
    <dict>
        <key>radar</key>
        <dict><key>args</key><array><string>mcp</string></array></dict>
    </dict>

（`command` 預設為區段鍵名，並在 PATH 上解析；這些伺服器會設定 `PULL_ROOT`）。
ycode 也會將這一切轉送給 Hermes 等 ACP 代理程式。
