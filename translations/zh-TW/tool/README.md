# tool

每個專案的宣告式 Homebrew 套件，有點像 nix profile。

- **套件清單**：Brewfile 格式（`tap`、`brew`）。獨立的 `tool` 會讀取 `Brewfile`；
  在 pull 工作區中，清單位於 pullfile 的 `tool` 區段（`pull tool`）。
- **儲存區**：一個共用的 Homebrew 配置前綴（`Cellar/<name>/<version>`、`opt/<name>`），位於
  `$TOOL_HOME`（預設為 `~/.local/share/tool`）。Kegs 是來自
  `formulae.brew.sh` / ghcr.io 的 Linuxbrew bottle，經倒入並重新定位至儲存區（ELF 直譯器 -> 系統
  載入器，RUNPATH -> `opt/<dep>/lib`，透過 `patchelf`）。Bottle 會快取在
  `$TOOL_CACHE`（預設為 `~/.cache/tool`）。
- **Profile**：由指向所要求 formula 的符號連結（`bin/`、`lib/`、`share/`
  ...）組成的資料夾，每次同步時都會重建並以原子方式換入。每個 profile 都是 GC 根；
  `tool gc` 會刪除沒有任何有效 profile 使用的 keg。

需要 `patchelf`。僅支援 homebrew/core 的 formula；cask/mas/vscode 項目會被忽略。
已規劃從原始碼建置 bottle；目前所有內容都是從 Linuxbrew bottle 倒入。

## 獨立使用

```sh
printf 'brew "jq"\nbrew "ripgrep"\n' > Brewfile
tool sync            # pour into the store, link ./.tool
eval "$(tool env)"   # .tool/bin on PATH
tool list
tool gc
```

## 在 pull 工作區中

```sh
pull tool add jq ripgrep      # pullfile `tool` = {brew = [jq, ripgrep]}, then sync
pull tool import Brewfile     # merge an existing Brewfile into the pullfile
pull tool sync                # links $PULL_ROOT/.pull/tool
pull env                      # PATH includes $PULL_ROOT/.pull/tool/bin
```

Pullfile 區段：

```xml
<key>tool</key>
<dict>
  <key>brew</key>
  <array>
    <string>jq</string>
    <dict><key>name</key><string>openssl@3</string><key>link</key><false/></dict>
  </array>
</dict>
```

建構於 stout crate 之上（stout-bundle、stout-fetch、stout-install、stout-resolve）。
