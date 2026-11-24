# ycode-hermes

ycode 的 Lua 外掛，透過 ACP（Agent Client Protocol）讓 [Hermes Agent](https://github.com/NousResearch/hermes-agent)
成為 ycode 的代理程式。

它會透過 ycode 記憶體內的外掛設定層，將 `hermes acp` 註冊為外部代理程式（`agent_servers.hermes`）。
你在代理程式面板中以「hermes」代理程式開始的執行緒會在 Hermes 內執行，因此它們是 Hermes session
（儲存在 Hermes 的 `state.db`），具備 Hermes 的記憶、技能、工具與模型提供者，包括 OAuth 類型的提供者。
ycode 不保存任何憑證；請用 `hermes model` 變更模型。

命令面板：

- **hermes: new thread**：以 Hermes 開啟新的代理程式面板執行緒
- **hermes: status**：ACP 檢查（`hermes acp --check`）、版本與 Hermes 的預設模型
- **hermes: sync threads**：立即在側邊欄顯示 Hermes session

## Hermes 外掛

`hermes-plugin/` 新增了 `hermes ycode-acp`：它是原版 ACP 轉接器，差別在於 `session/list`
與 `session/load` 也包含 CLI、TUI/桌面與 gateway session（原版 `hermes acp` 只
顯示編輯器建立的 session）。子代理程式、cron 與單次 session 仍會隱藏。
只需安裝一次：

    # from the ycode-hermes clone
    ln -s "$PWD/hermes-plugin" ~/.hermes/plugins/ycode-hermes
    hermes plugins enable ycode-hermes

## 側邊欄

來自各種介面（CLI、gateway、其他編輯器）的 Hermes session 會透過 ACP
（`session/list`）列出，並在啟動 5 秒後以執行緒顯示於側邊欄，之後
每 2 分鐘一次，透過 ycode 的 `agent::SyncAgentThreads` 動作。只會顯示工作
目錄是已開啟資料夾或其子目錄的 session；來自其他目錄的 Hermes 執行緒會從側邊欄移除
（它們仍保留在 Hermes 中，並在其資料夾開啟時回來）。開啟其中一個時
會從 Hermes 載入（`session/load`）。

啟動時，外掛會在 PATH 上解析 `hermes`，並在背景執行 ACP 檢查。

## 安裝

    # from the ycode-hermes clone
    ln -s "$PWD" ~/.config/zed/hooks/ycode-hermes

然後執行「ycode: reload hooks」。
