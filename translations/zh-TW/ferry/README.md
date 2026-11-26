# Ferry

iOS 側載（sideloading）工具，適用於 Linux，以 Zig 編寫：簽署 IPAs 並透過 USB
或 Wi-Fi 安裝。有一個守護程序（daemon）負責管理裝置與工作、一個 CLI (`ferry`) 和一個
GUI (`ferry-gui`，基於 dvui/SDL3)。

Jimpactor 的後繼架構。請參閱 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
了解變更內容及原因。

## 建置

需要 Zig 0.17.1 以及 libimobiledevice、libplist、libzip、OpenSSL 和
FreeType 開發套件，並需有正在運行的 `usbmuxd`。

```sh
zig build                 # zig-out/bin/{ferry,ferryd,ferry-gui}
zig build -Dgui=false     # 僅 CLI + 守護程序
zig build test            # 每個模組的測試，各模組獨立進行
```

部分相依套件（translate-c）位於 codeberg.org。如果您的 DNS 無法解析該網域，`tools/fetch-codeberg.sh <owner/repo> <commit> <hash>` 會透過 1.1.1.1 下載
並填充套件快取。

`tools/install-desktop.sh` 為 `ferry-gui` 新增啟動器項目和圖示。
`FERRY_GUI_SCREENSHOT=out.png ferry-gui` 會渲染一幀至 PNG 並退出。

## 從 Jimpactor 遷移

```sh
ferry import jimpactor        # 或點擊「從 Jimpactor 匯入」按鈕
```

這會複製 Jimpactor 的配對記錄（裝置出現時傳遞給 usbmuxd），並將每個 `xkit/data/<TEAM>` 憑證 + 金鑰轉換為身份
`jimpactor-<TEAM>`。Jimpactor 不保留設定檔（provisioning profiles），因此該
身份在首次簽署每個應用程式時會向 `jimpactor-cli`（透過 `$JIMPACTOR_CLI`、`PATH` 或
`~/projs/jimpactor/target` 找到）請求設定檔，並將其快取於 `identities/jimpactor-<TEAM>/profiles/`。Wi-Fi 裝置清單、
Tailscale 金鑰和 anisette 資料則未被使用。

## 使用

```sh
ferry import jimpactor
ferry identity add team --p12 cert.p12 --password ... --profile app.mobileprovision
ferry devices
ferry install MyApp.ipa                  # 連接了一個裝置
ferry install "JP's iPhone" MyApp.ipa -b com.me.myapp
ferry sign MyApp.ipa -o signed.ipa
ferry apps / info / uninstall <bundle>
ferry watch                              # 即時裝置 + 工作事件
ferry daemon start|stop|status
ferry schema                             # 協定 JSON Schema
```

`ferry` 若有運行的守護程序則會使用它，因此其工作也會顯示在
GUI 中。否則，它會在進程內執行所有操作。GUI 會自行啟動守護程序。資料存放在 `$FERRY_HOME`，或 `~/.config/ferry`。
通訊端為 `$XDG_RUNTIME_DIR/ferry.sock`。

## 語言

英文和繁體中文（zh_TW）。語言設定遵循 `LANG` /
`LC_MESSAGES` / `LANGUAGE`（zh_TW、zh_HK 和 zh_Hant 皆會選取 繁體中文），或
`FERRY_LANG=zh_TW` 強制指定。GUI 也在標頭中提供語言選擇器。GUI 使用桌面的介面字型（GNOME `font-name`，透過
fontconfig）以及，對於中文，使用系統的 Noto Sans CJK TC。

翻譯為 GNU gettext 目錄檔，位於 `po/`。它們在建置時以
`msgfmt --check` 編譯並嵌入二進位檔案中，因此即使系統上未產生 `zh_TW` 區域設定也能運作。要新增字串：
將其包裝在 `tr("...")` 中（或 `trf`/`trl`/`failT`/`say`，帶有 `{0}`
佔位符），執行 `zig build pot`，然後
`msgmerge -U po/zh_TW.po po/ferry.pot`，並翻譯新的條目。

`tests/make-test-identity.sh DIR` 建立一個一次性憑證和設定檔，
讓您可以嘗試簽署而無需 Apple 帳戶。裝置不會接受以其簽署的應用程式。
