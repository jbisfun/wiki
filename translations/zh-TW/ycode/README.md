# ycode

ycode 是 [Zed](https://github.com/zed-industries/zed) 的分支，可以用
Lua 編寫腳本。它自己的程式碼是一套 hook 系統，即 [`crates/lua_hooks`](crates/lua_hooks)。
它讓以 Lua 撰寫的外掛可以攔截並取代任何 Zed 動作、新增動作，並繪製
原生 gpui 視窗與停駐面板。編輯器的其餘部分就是上游的 Zed，只加上少量
小型修補。

ycode 是 [jbisfun](https://github.com/jbisfun) 工作區的一部分，該工作區以
[pull](https://github.com/jbisfun/pull) 管理。大多數功能都在外掛中，而不在這個
儲存庫裡。

## Lua hooks

Hook 檔案為 `~/.config/zed/hooks/*.lua` 與 `*.x.lua`，另外加上一層擴充功能
子資料夾（`hooks/<ext>/`）。`.x.lua` 檔案使用仿照
[Logos](https://theos.dev/docs/logos-syntax) 的指令：

```lua
%hook editor
- Copy
  %log
  %orig
end
%end
```

- `%hook ns` / `- Action`：包裝 `ns::Action`（`- *` 會包裝整個命名空間）。如果
  hook 從未呼叫 `%orig`，該動作就會被吞掉。
- `%new - Name(args)`：新的動作，會顯示在命令面板中。
- `%hookf point`：包裝 Rust 程式碼中的 hook 點（例如 `client::authenticate`，即啟動時的
  自動登入）。
- `%ctor`、`%group`/`%init`、`%log`。

Lua API（`ycode.*`、`gpui.*`）涵蓋派送動作、設定層、KV
儲存、狀態列按鈕、工作區資料夾、產生處理程序與原生 UI 元素
（`gpui.open_window`、`gpui.register_panel`）。內嵌了 LuaSocket。外掛可
透過 `ycode: reload hooks` 重新載入，完全不需要重新建置。

- [crates/lua_hooks/README.md](crates/lua_hooks/README.md)：指令與 API
- [crates/lua_hooks/UI.md](crates/lua_hooks/UI.md)：Lua 視窗與面板應有的外觀
- `crates/lua_hooks/ycode-lua`：即時執行器 socket 的 REPL／執行器
  （`$XDG_RUNTIME_DIR/ycode-lua.sock`）

## 外掛

每個外掛都是獨立的儲存庫，以符號連結連到 `~/.config/zed/hooks/<name>/`：

- [ycode-pull](https://github.com/jbisfun/ycode-pull)：pull 的多儲存庫 Pull 面板、
  session 與工作。它取代了只能處理單一儲存庫的 Zed git 面板。
- [ycode-hermes](https://github.com/jbisfun/ycode-hermes)：以 Hermes Agent 作為代理程式，
  透過 ACP
- [ycode-idl](https://github.com/jbisfun/ycode-idl)：idl CLI 的面板
- [ycode-manager](https://github.com/jbisfun/ycode-manager)：啟用／停用外掛
- [ycode-offline](https://github.com/jbisfun/ycode-offline)：關閉登入與
  線上功能

## 對 Zed 的變更

在 `crates/lua_hooks` 之外，修補都很小而且通用：

- gpui：`App::intercept_actions`，單一插槽，包裝每一次視窗與全域
  動作的派送
- zed：`lua_hooks::init` 在所有其他初始化之後執行。啟動時的登入會經由
  `client::authenticate` hook 點。Lua C API 已匯出，讓 `require` 可以載入 C
  模組。
- settings：外掛設定層（`SettingsStore::set_plugin_settings`）
- 命令面板：`%new` 動作會出現在面板中，動作也可以隱藏
- workspace：Lua 停駐面板（`panel_index_for_id`）
- agent_ui：`agent::SyncAgentThreads` 會匯入 ACP 代理程式既有的 session

## 建置

建置方式與上游 Zed 相同（[Linux](docs/src/development/linux.md)、
[macOS](docs/src/development/macos.md)、[Windows](docs/src/development/windows.md)）：

```sh
cargo build -p zed        # target/debug/zed
```

## 授權

ycode 的授權方式與上游 Zed 相同：GPL-3.0-or-later，標示處則為 Apache-2.0 元件。
請參閱 `LICENSE-GPL` 與 `LICENSE-APACHE`。
