# ycode-radar

在 [ycode](https://github.com/jbisfun/ycode) 中使用 [radar](https://github.com/jbisfun/radar)，以 Lua 擴充功能的形式提供。

- **radar: panel** 會開啟右側停駐面板，顯示 pull 工作區中未結的報告，並依儲存庫分組。點擊報告即可在該行開啟其檔案。將滑鼠移到報告上即可關閉它。
- **radar: report** 會提交目前編輯器的選取內容。小視窗會顯示它指向何處與選取的文字，並附有備註輸入框。Ctrl-Enter 提交，Escape 取消。

報告會透過 `radar` CLI 寫入 `$PULL_ROOT/issues/radar.db`。工作區為 `$PULL_ROOT`，否則是 ycode 中已開啟資料夾上層最近的 `pullfile.plist`。

在 `keymap.json` 中將報告動作綁定到按鍵：

```json
{ "context": "Editor", "bindings": { "ctrl-alt-r": ["ycode::Run", { "name": "radar::Report" }] } }
```

## 安裝

將儲存庫連結到 hooks 資料夾，然後重新載入 hooks：

```sh
ln -s ~/jbisfun/ycode-radar ~/.config/zed/hooks/ycode-radar
```
