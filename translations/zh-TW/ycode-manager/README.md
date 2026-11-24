# ycode-manager

[ycode](https://github.com/jbisfun/ycode) Lua hooks 的模組管理員。狀態列中的按鈕（積木圖示），
或命令面板中的「manager: open」，會開啟一個視窗，列出 `~/.config/zed/hooks` 中的每個模組，
並顯示其說明（hook 檔案的第一行註解）、連結到哪裡，以及是否已啟用。

停用會將模組移到 `hooks/.disabled/`（載入器會略過以點開頭的資料夾）；啟用則
移回原處。「Reload hooks」會套用變更並重新開啟管理員。

## 安裝

    # from the ycode-manager clone
    ln -s "$PWD" ~/.config/zed/hooks/ycode-manager

然後執行「ycode: reload hooks」。需要具備 `ycode.status_button` 的 ycode。
