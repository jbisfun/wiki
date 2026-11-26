# ycode-tweaks

[drew-council/zed-config](https://github.com/drew-council/zed-config) 移植為 ycode
Lua 外掛程式 (`tweaks.x.lua`)：

- settings.json 透過 `ycode.settings{}` 進入 ycode 的記憶體中外掛程式層：
  Catppuccin 主題與圖示、vim 模式、VSCode 基礎按鍵映射、左側停靠面板、右側代理程式、自動儲存、自動安裝的外掛程式與每種語言的選項。不會寫入磁碟，且使用者的 settings.json 仍會覆蓋它。
- keymap.json 繫結來自 `%hookf keymap::user`。它們被前置，因此您自己的
  keymap.json 優先。
- lazygit 工作 (`ctrl-shift-space`) 來自 `%hookf tasks::global`。

與上游的差異：

- 終端機殼層僅在 nu 已安裝時設定為 `nu`。
- `edit_predictions.provider = "zed"` 被移除。它需要 zed.dev 登入，且會
  覆蓋 ycode-offline。
- 範例「Example task」與 nix flake/treefmt/pre-commit 工具組被省略。

## 安裝

    ln -s "$PWD" ~/.config/zed/hooks/ycode-tweaks

然後執行「ycode: 重新載入 hooks」。

GPL-3.0，與上游相同。
