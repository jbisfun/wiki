# ycode-idl

在 ycode 中使用 [idl](https://github.com/jbisfun/idl)，是建立在 ycode 的
`lua_hooks`（`gpui.register_panel`）上的 Lua 擴充功能。

一個右側停駐面板（「idl: panel」），對應位於已開啟資料夾本身、其上層，或其下一至
兩層的 idlproj.yml（pull 工作區會把儲存庫放在下一層）：

- 來自 `idl list` 的目標；可選擇一個或全部
- debug / release 設定檔與 `--strict`
- Build、Install、Check、Test、Gen、Lint、Fmt、Clean
- 來自 Jimpactor 系統匣應用程式的裝置（`idl devices list`）；Install 會將 IPA 交給
  所選的裝置
- 帶有 Stop 按鈕的串流輸出；`file:line:col: error:` 行會被醒目標示，
  點擊後會開啟對應檔案

「idl: build」與「idl: install」可從命令面板以面板的選擇執行。

## 安裝

    ln -s "$PWD" ~/.config/zed/hooks/ycode-idl

然後執行「ycode: reload hooks」。`idl` 必須位於 ycode 的 PATH 上。
