# idlproj.yml 參考

`idlproj.yml` 是唯一的設定檔。它有四個頂層鍵：

```yaml
toolchain: { ... }   # optional: where the compilers and SDK live
defaults:  { ... }   # optional: target keys applied to every target
configurations: { ... } # optional: debug/release overrides
targets:   [ ... ]   # required: one entry per app
```

`idl` 會拒絕未知的鍵，因此像 `sorces:` 這樣的拼字錯誤會變成錯誤，而不是被忽略。版本號請寫成文字，也可以加上引號：`min_ios: 16.0` 與 `min_ios: "16.0"` 都代表字串 `16.0`，而 `16.10` 絕不會被讀成浮點數。

## toolchain

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `sdk_bundle` | `~/.swiftpm/swift-sdks/darwin.artifactbundle` | 來自 `xtool setup` 的 Darwin SDK bundle |
| `sdk` | bundle 中最新的 `iPhoneOS*.sdk` | 明確指定的 SDK 路徑 |
| `swiftly_bin` | `~/.local/share/swiftly/bin` | 附加到 idl 所執行每個工具的 `PATH` 末端 |
| `cc` / `cxx` / `swiftc` | `clang` / `clang++` / `swiftc` | 編譯器，依名稱在 `PATH` 上尋找，或直接給定路徑 |
| `xtool` | `xtool` | xtool 可執行檔（`builder: xtool` 需要） |
| `ldid` | `ldid` | ldid 路徑或指令名稱（目標需要簽署時使用） |
| `jobs` | `0` | 平行編譯工作的數量（`0` = CPU 數量） |
| `actool` | `idl-actool` | 資產目錄編譯器（`zig build actool`）；可為路徑，或在 PATH 與 `idl` 旁尋找的名稱 |
| `appintents` | `appintentsmetadataprocessor` | App Intents 中繼資料處理器（[re-appintentsmetadataprocessor](https://codeberg.org/viraptor/re-appintentsmetadataprocessor)，與 Xcode 的 CLI 相同）；可為路徑或 PATH 上的名稱。`app_intents` 目標需要它 |
| `jimpactor_dir` | `$XDG_CONFIG_HOME/Jimpactor` 或 `~/.config/Jimpactor` | Jimpactor 資料夾，供 `idl devices` 與 `idl install` 使用 |

路徑中的 `~` 會被展開。

## targets

每個目標是一個對應（mapping）。目標內的路徑相對於其 `dir`，且必須位於其內（不可使用絕對路徑，也不可使用 `..`）。

### Identity

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `name` | 必填 | 產品名稱、可執行檔名稱，以及 Xcode 目標名稱 |
| `bundle_id` | 必填 | `CFBundleIdentifier` |
| `dir` | `.` | 目標資料夾，相對於 `idlproj.yml` |
| `builder` | `direct` | `direct`（idl 執行 clang/swiftc）或 `xtool`（idl 執行 `xtool dev build`） |
| `version` | `1.0` | `MARKETING_VERSION` / `CFBundleShortVersionString` |
| `build_number` | `1` | `CURRENT_PROJECT_VERSION` / `CFBundleVersion` |
| `min_ios` | `16.0` | 部署目標、triple 後綴與 `MinimumOSVersion` |

### Sources and compilation

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `sources` | `[Sources]` | 檔案或資料夾，會遞迴掃描。支援：`.c .m .mm .cc .cpp .cxx .s .S .swift` |
| `arch` | `arm64` | 目標架構 |
| `opt` | `-Os` | C 系列程式碼的最佳化旗標 |
| `swift_opt` | `-O` | Swift 的最佳化旗標 |
| `debug_symbols` | `false` | 在 C 系列與 Swift 物件檔中輸出 DWARF |
| `strict` | `false` | 拒絕不支援的資源與 IB 功能，而不是警告／略過 |
| `swift_version` | `5.0` | 寫入 Xcode 專案 |
| `defines` | `[]` | `NAME` 或 `NAME=VALUE`。兩種形式都會傳給 C 系列程式碼；只有 `NAME` 會傳給 Swift |
| `include_dirs` | `[]` | 給 clang 與 swiftc 的 `-I` |
| `bridging_header` | 無 | Swift 匯入的 Objective-C 標頭（`-import-objc-header`） |
| `quote_include_dirs` | `[]` | `-iquote` 資料夾（clang，以及透過 `-Xcc` 的 swiftc）：只有 `#include "..."` 看得到它們，與 Xcode 的 header map 相同 |
| `framework_dirs` | `[]` | 給 clang、swiftc 與連結器的 `-F` 資料夾 |
| `dead_strip` | `true` | 將 `-dead_strip` 傳給連結器 |
| `cflags` / `swiftflags` | `[]` | 額外的編譯器旗標 |
| `ldflags` | `[]` | 額外的連結器引數，每個都以 `-Xlinker <arg>` 傳遞 |
| `frameworks` | `[UIKit, Foundation]` | SDK framework（`X` 或 `X.framework`） |
| `weak_frameworks` | `[]` | 弱連結的 framework |
| `libraries` | `[]` | `-l` 函式庫，例如 `[z, sqlite3]` |
| `build_dir` | `build` | 物件檔、應用程式 bundle 與 IPA 的存放位置 |
| `app_intents` | 當 `frameworks` 含有 `AppIntents` 或 `WidgetKit`，或所連結的 static 目標含有 intent 時為開啟 | 將 App Intents 中繼資料擷取到 `Metadata.appintents`（見下文） |

若目標含有任何 `.swift` 檔案，swiftc 會以單一整個模組編譯所有 Swift 來源，並連結由 clang 編譯的物件檔。Debug 建置會將 Swift 編譯成持久的 `.swift.o` 並另外連結，保留 DWARF 而不需要 `dsymutil`。否則由 clang 連結。C++ 來源會加上 `-lc++`。

### App Intents metadata

iOS 會讀取 bundle 的 `Metadata.appintents` 來找出它的 App Intents：Shortcuts 動作、`AppIntentConfiguration` 小工具設定，以及互動式小工具按鈕（`Button(intent:)`）。沒有它的話，intent 雖然能編譯但永遠不會執行。對於 `app_intents` 目標（應用程式、appex 或 framework），idl 會執行 Xcode 的 ExtractAppIntentsMetadata 步驟所做的事：

1. swiftc 寫出模組的常數值（`-emit-const-values-path`，並以 App Intents 協定清單作為 `-const-gather-protocols-file`）。
2. 連結之後，`toolchain.appintents` 會讀取二進位檔、來源與常數值（`--compile-time-extraction`），並寫出 `<obj>/appintents/Metadata.appintents`（`extract.actionsdata`、`version.json`）。
3. bundle 會在其根目錄取得它，例如 `PlugIns/Widgets.appex/Metadata.appintents`。

含有 `app_intents` 的 `static` 目標只會記錄其常數值；每個連結它的 bundle 會將該 static 模組與自己的模組一併擷取（因此由應用程式與其小工具擴充功能共用的 intent，例如必須在應用程式中執行的 `AudioPlaybackIntent`，會放在由兩者連結的同一個 static 目標中）。連結這樣的目標會為該 bundle 開啟擷取功能。

未宣告任何 intent 的模組不會產生中繼資料。在預設情況下（`frameworks` 中有 WidgetKit/AppIntents），缺少處理器只會是警告；使用 `app_intents: true` 或 `--strict` 時則是錯誤。`app_intents: false` 會將它關閉。

WidgetKit 擴充功能是一個 `appex`，具有 Swift 的 `@main WidgetBundle`，且 `ldflags` 中沒有進入點：

```yaml
  - name: Widgets
    type: appex
    bundle_id: com.example.app.widgets
    min_ios: "17.0"
    sources: [Widgets]
    frameworks: [SwiftUI, WidgetKit, AppIntents]
    info:
      NSExtension:
        NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

### Bundle

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `info_plist` | 無 | 選用的基底 Info.plist（XML、二進位、JSON 或 OpenStep）；否則完全由 YAML 產生 |
| `info` | 無 | 合併到 Info.plist 的鍵（見下文） |
| `plist_vars` | 無 | Info.plist 與 entitlements 額外的 `$(VAR)` 值 |
| `entitlements` | 無 | entitlement 鍵的 YAML 對應，或明確的舊版 plist 路徑；不會隱含加入任何 capability |
| `resources` | `[]` | 複製到 bundle 中的檔案或資料夾（請參閱[限制](limitations.md)） |
| `sign` | `direct` 為 `true`，`xtool` 為 `false` | 以 ldid 進行 ad-hoc 簽署／將 `--sign` 傳給 xtool |
| `app_icon` | `AppIcon` | Xcode 專案中的資產目錄圖示名稱 |
| `icon` | 無 | 僅限 xtool 目標：複製到應用程式根目錄並設為 `CFBundleIconFile` 的 PNG（xtool 的 `iconPath`） |
| `device_family` | `1,2` | 產生的 `UIDeviceFamily` 與 Xcode 的 `TARGETED_DEVICE_FAMILY` |

Info.plist 的處理依序如下：

1. 從空字典（或明確的 `info_plist` 基底）開始。加入任何缺少的標準鍵：`CFBundleExecutable`、`CFBundleIdentifier`、`CFBundleName`、`CFBundlePackageType`、`CFBundleInfoDictionaryVersion`、`CFBundleShortVersionString`、`CFBundleVersion`。同時將顯示名稱預設為目標名稱，開發地區預設為 `en`，`LSRequiresIPhoneOS` 預設為 true，裝置家族預設為 `device_family`，方向預設為直向，並且除非設定了啟動 storyboard，否則 `UILaunchScreen` 預設為空字典。
2. 合併 `info:` 對應。未加引號的 `true`/`false` 會變成布林值，未加引號的整數會變成 `<integer>`，清單會變成陣列，對應會變成字典，加引號的值則維持為字串。像 `CFBundleVersion` 這類版本鍵一律維持為字串。
3. 將 `MinimumOSVersion` 設為 `min_ios`。
4. 對於 direct 建置，合併資產編譯器產生的圖示鍵。
5. 展開每個字串中的 `$(VAR)`、`${VAR}` 與 `$(VAR:modifier)`。值依序來自 `plist_vars`、內建變數，然後是環境變數。未知的變數會變成空字串。modifier 會被忽略。

內建變數：`EXECUTABLE_NAME`、`PRODUCT_NAME`、`TARGET_NAME`、`PRODUCT_MODULE_NAME`、`PRODUCT_BUNDLE_IDENTIFIER`、`PRODUCT_BUNDLE_PACKAGE_TYPE`、`MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、`IPHONEOS_DEPLOYMENT_TARGET`、`DEVELOPMENT_LANGUAGE`。

不需要手寫 XML：

```yaml
targets:
  - name: MyApp
    bundle_id: com.example.myapp
    version: "1.0"
    build_number: "1"
    info:
      CFBundleDisplayName: My App
      NSCameraUsageDescription: Take a profile photo
      UIMainStoryboardFile: Main
      UILaunchStoryboardName: LaunchScreen
      UIBackgroundModes: [audio]
    entitlements:
      get-task-allow: true
      com.apple.security.application-groups: ["group.com.example.myapp"]
```

若是程式化建立的 UI，請省略 storyboard 鍵。不需要任何 capability 時，請省略 `entitlements`；`get-task-allow` 是需要時才選用，並非 release 的預設值。Entitlements 支援與 `info` 相同的 YAML 型別與變數展開。它們只是請求，並非佈建：Apple 的 capability 仍然需要適當的簽署身分／描述檔。明確指定的 `info_plist` 或字串值的 `entitlements: Support/App.entitlements` 仍然受到支援。缺少的明確檔案會是錯誤，絕不會被默默忽略。

`idl gen` 與 `idl xcodeproj` 會在每個目標資料夾內寫入 `.idl/Info.plist`，並在有設定時寫入 `.idl/Entitlements.plist`。Xcode 與 xtool 會參照這些產生的檔案。編輯 YAML 後，請先執行 `idl gen`，再於 Xcode 中建置。`.idl/debug/` 與 `.idl/release/` 兩組中繼資料也會一併產生；Xcode 的設定會參照與其對應的那一組。變數會在產生時依各設定檔展開，並不會由 Xcode 從 YAML 重新求值。Direct 建置會自行產生 bundle 中繼資料；xtool 的中繼資料會在每次 xtool 建置前重新產生。`.idl/` 是可拋棄的，應加入 gitignore。

### Products

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `type` | `app` | `app`、`framework`、`dylib`、`appex` 或 `static` |
| `link` | `[]` | 要連結的專案 `framework`/`dylib`/`static` 目標 |
| `embed` | `[]` | 僅限應用程式：要複製到 bundle 中的專案 `framework`/`dylib`/`appex` 目標 |
| `post_build` | `[]` | 僅限應用程式：IPA 建置並驗證後，依序執行的指令（argv 清單）或指令清單；可用 `idl build --no-post-build` 略過 |

`idl build X` 會建置 X 以及它所連結或嵌入的每個目標，並先建置相依項目。循環相依是錯誤。每種類型會產生：

- `framework`：`<build>/products/<name>.framework`（二進位檔、帶有 `FMWK` 的產生 Info.plist、資源），install name 為 `@rpath/<name>.framework/<name>`，bundle 以 ldid 簽署。相依者以 `-F <build>/link -framework <name>` 連結。應用程式會將它嵌入 `Frameworks/` 之下。
- `dylib`：`<build>/products/<name>.dylib`，install name 為 `@rpath/<name>.dylib`，嵌入 `Frameworks/` 之下。沒有 `bundle_id`、Info.plist 或資源。
- `appex`：`<build>/products/<name>.appex`（帶有 `XPC!` 的 Info.plist、entitlements，以 `-I<bundle_id>` 簽署），以 `-fapplication-extension` / `-application-extension` 建置。Rpath 包含 `@executable_path/../../Frameworks`。應用程式會將它嵌入 `PlugIns/` 之下。進入點來自 `ldflags`（例如給鍵盤這類主要類別擴充功能的 `[-e, _NSExtensionMain]`），或 Swift 的 `@main`（WidgetKit `WidgetBundle`、ExtensionKit）。
- `static`：編譯後的物件檔加上 `<name>.swiftmodule` 與 `<name>-Swift.h`。進行連結的目標會在其連結中收到這些物件檔，以及模組的 `-I` 與標頭資料夾。不簽署。沒有 `bundle_id`。

非應用程式目標中的 Swift 會以 `-parse-as-library` 與模組名稱 `<name>` 編譯。`post_build` 會在目標資料夾中執行，並設定 `IDL_IPA`、`IDL_APP`、`IDL_BUILD_DIR`、`IDL_TARGET`、`IDL`（正在執行的 idl 的路徑），以及在使用 `-c` 時設定 `IDL_CONFIGURATION`。以非零狀態結束的指令會使建置失敗。

在 `info:` 中，`Key: ~` 會移除從 `info_plist` 繼承的鍵。Info.plist 與 entitlement 的展開也可以使用來自專案根目錄 git 工作目錄的 `$(GIT_BRANCH)` 與 `$(GIT_COMMIT)`（環境變數會覆寫它們）。來源與資源項目可以在其最後一個路徑元件中使用 `*`，例如 `Resources/*.lproj`。

### Formatting, linting and tests (`idl fmt`, `idl lint`, `idl test`)

idl 只負責協調這些工具。它會從 YAML 將其設定產生到 `.idl/quality/<target>/` 中，因此不需要手寫的 `.clang-format` 或 `.swift-format` 檔案。它會明確傳遞設定、平行執行這些工具，並將其輸出合併成一份去除重複的報告：`file:line:col: severity: message [flag] (tool)`，接著是各工具的摘要，以及最常出現的旗標／檢查。

`format:`（對應會與 `defaults:` 合併）：

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `indent` | `4` | 縮排寬度（clang-format 的 `IndentWidth`/`ObjCBlockIndentWidth`，swift-format 的 `indentation.spaces`） |
| `line_length` | `0` | 0 = 永不重新換行（clang-format `ColumnLimit: 0`） |
| `clang_format` | 無 | 額外的 clang-format 鍵；會覆寫產生的鍵（允許巢狀對應） |
| `swift_format` | 無 | 額外的 swift-format JSON 鍵，以深層合併（例如 `rules:`） |
| `exclude` | `[]` | 永不格式化的來源路徑或資料夾（每個路徑元件可用 `*`） |
| `editor_configs` | `false` | `idl gen` 也會寫入 `.clang-format`、`.clang-tidy` 與 `.swift-format`，供 clangd/sourcekit-lsp 使用 |

`idl fmt [--check] [target...]` 會以 clang-format 格式化 C、Objective-C、C++、Objective-C++ 與標頭檔，並以 swift-format 格式化 Swift。`--check` 不會變更任何內容，且若有任何檔案會被變更就以 1 結束。

`lint:`：

| 鍵 | 預設值 | 說明 |
| --- | --- | --- |
| `warnings` | `[-Wall]` | 加入編譯器階段的 clang 警告旗標 |
| `swift_flags` | `[]` | Swift 型別檢查額外的 swiftc 旗標 |
| `exclude` | `[]` | 不進行 lint 的路徑；位於這些路徑的診斷訊息也會被捨棄 |
| `clang_tidy` | auto | 執行 clang-tidy（auto = 已安裝時） |
| `clang_tidy_checks` | idl 的集合 | clang-tidy 的 `Checks`；預設為 clang-analyzer、bugprone 與 performance 檢查，並排除較吵雜的項目 |
| `analyze` | `false` | 同時執行 clang 靜態分析器（`clang --analyze`） |
| `swift_format` | `false` | 同時以產生的樣式執行 `swift-format lint` |

`idl lint [target...]` 會先以增量方式建置目標及其相依項目，讓 Swift 模組與產生的 `<Module>-Swift.h` 標頭存在。接著它會以目標的確切建置旗標重新執行每個編譯器。每個 C 系列檔案會執行 `clang -fsyntax-only`，並移除目標的 `-w`、`-Werror` 與 depfile 旗標，再加入 `lint.warnings`。每個 Swift 模組會執行啟用警告的 `swiftc -typecheck`。clang-tidy、靜態分析器與 `swift-format lint` 會重複使用相同的旗標。來自 SDK、被排除路徑的診斷訊息，以及同一標頭警告在多個編譯單元間的重複項目都會被捨棄。選項：`--werror`、`--analyze`、`--tidy`/`--no-tidy`、`-q`（僅摘要）與 `--max N`。錯誤會以 1 結束，使用 `--werror` 時警告也是。

`tests:`（僅限應用程式）是指令清單（argv 清單）。`idl test [target...]` 會建置目標而不執行 `post_build`（除非使用 `--no-build`）。接著它會檢查每個應用程式已建置的 bundle：
- 每個 Mach-O 都必須是 arm64、為 iOS 建置且已簽署。嵌入的程式碼不得要求比應用程式的 MinimumOSVersion 更新的 iOS；擴充功能則除外。
- 每個 `@rpath`/`@loader_path`/`@executable_path` 相依項目都必須能在 bundle 內解析，使用映像本身的 rpath。系統函式庫必須存在於 SDK 中。私有 framework 與弱連結只會產生警告。
- 每個 framework 與擴充功能都需要 Info.plist 與可執行檔，且版本鍵為字串。
- 每個擴充功能的 bundle ID 都必須以應用程式的 bundle ID 為前綴，且必須具有 `NSExtension`/`EXAppExtensionAttributes`。

檢查之後，`tests:` 指令會在目標資料夾中執行，並設定 `IDL_IPA`、`IDL_APP`、`IDL_BUILD_DIR`、`IDL_TARGET` 與 `IDL`。輸出是每個檢查或指令各一行 PASS/FAIL，然後是摘要。

工具路徑可在 `toolchain:` 下以 `clang_format`、`clang_tidy` 與 `swift_format` 設定（swift-format 隨 swiftly 工具鏈提供）。缺少的選用工具會被略過並附上說明。

### Code generation

| 鍵 | 預設值 | 產生 |
| --- | --- | --- |
| `xcodeproj` | `false` | `<dir>/<name>.xcodeproj`（專案 + 共用 scheme） |
| `compile_commands` | `false` | `<dir>/compile_commands.json`（僅限 direct 目標） |
| `package_swift` | `true` | `<dir>/Package.swift`（僅限 xtool 目標） |
| `configuration` | `release` | xtool 建置設定（`debug`/`release`） |

xtool 目標一律會產生 `xtool.yml`。產生的檔案開頭會有 `Generated by idl from idlproj.yml` 標記，而 `idl` 拒絕覆寫沒有該標記的檔案。若要保留手寫的 `Package.swift`，請設定 `package_swift: false`。

xtool 目標必須恰好有一個 `sources` 項目：即 SwiftPM 目標資料夾。

## configurations

在 `build`、`install`、`check`、`gen`、`xcodeproj`、`list` 與 `clean` 上以 `-c debug` / `--configuration release` 選取：

```yaml
configurations:
  debug:
    info:
      CFBundleDisplayName: My App Debug
  release:
    defines: [PRODUCTION]
    entitlements:
      get-task-allow: false

targets:
  - name: MyApp
    bundle_id: com.example.myapp
    configurations:
      debug:
        bundle_id: com.example.myapp.debug
        entitlements:
          get-task-allow: true
```

內建的 debug 設定：`opt: -O0`、`swift_opt: -Onone`、`debug_symbols: true`，以及額外的 `DEBUG` 定義。內建的 release 設定：`-Os`、`-O`、無 DWARF；繼承而來的 YAML `get-task-allow` 會設為 false。設定檔覆寫可以明確變更這些預設值。對於未請求任何 capability 的應用程式，不會憑空產生 entitlement 檔案。對於舊版 entitlement 檔案輸入，如有需要，請在 release 設定檔中明確覆寫 entitlements。

優先順序，由低到高：`defaults` -> 目標 -> 內建設定檔 -> 全域 `configurations.<name>` -> 目標的 `configurations.<name>`。對應會遞迴合併，清單是取代而非附加，而 `~` 會清除選用的值。`DEBUG` 會在 debug 建置合併之後附加。

支援的設定檔覆寫：`bundle_id`、`opt`、`swift_opt`、`debug_symbols`、`defines`、`info`、`entitlements`、`plist_vars`、`build_dir`、`cflags`、`swiftflags`、`ldflags`、`strict`、`sign`。目標、來源清單與相依項目不會隨設定檔而異。未知的設定檔名稱／鍵會是錯誤。

設定檔的輸出路徑是 `<build_dir>/debug/` 與 `<build_dir>/release/`，兩種建置器皆然（xtool 的 IPA 會被複製到該設定檔路徑）。Xcode 會收到相符的最佳化、定義、除錯符號、簽署與中繼資料設定。未使用 `-c` 時，會保留舊版旗標與輸出路徑；舊的目標 `configuration:` 鍵仍會選擇 xtool 底層的設定。

## defaults

`defaults:` 接受除了 `name`、`dir` 與 `bundle_id` 之外的任何目標鍵。目標對於對應（`info`、`entitlements` 等）會遞迴覆寫預設值；清單是被取代，而非合併，而 `~` 會清除選用的對應／值。

## Complete example

```yaml
toolchain:
  jobs: 8

defaults:
  min_ios: "16.0"
  compile_commands: true

targets:
  - name: MyApp
    dir: app
    bundle_id: com.example.myapp
    version: "2.1"
    build_number: "37"
    sources: [Sources]
    resources: [Resources]
    bridging_header: Sources/MyApp-Bridging-Header.h
    defines: [ENABLE_LOGGING, 'API_HOST="api.example.com"']
    frameworks: [UIKit, Foundation, AVFoundation]
    libraries: [z]
    entitlements:
      get-task-allow: true
    plist_vars:
      APP_GROUP: group.com.example.myapp
    info:
      CFBundleDisplayName: My App
      UIFileSharingEnabled: true
      UIBackgroundModes: [audio]
    xcodeproj: true

  - name: Companion
    builder: xtool
    dir: companion
    bundle_id: com.example.companion
    sources: [Sources/Companion]
    info:
      CFBundleDisplayName: My App
    frameworks: [UIKit]
```
