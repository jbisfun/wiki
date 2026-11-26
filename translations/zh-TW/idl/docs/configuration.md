# idlproj.yml 參考文件

`idlproj.yml` 是唯一的設定檔。它包含四個頂層鍵（keys）：

```yaml
toolchain: { ... }   # 選填：編譯器與 SDK 的位置
defaults:  { ... }   # 選填：套用至所有目標的預設鍵
configurations: { ... } # 選填：除錯/發布模式的覆寫設定
targets:   [ ... ]   # 必填：每個應用程式各佔一筆
```

`idl` 會拒絕未知的鍵，因此像是 `sorces:` 這樣的拼字錯誤會被視為錯誤而非忽略。版本號碼以文字形式書寫，您可以選擇加上引號：`min_ios: 16.0` 與 `min_ios: "16.0"` 皆表示字串 `16.0`，且 `16.10` 永遠不會被讀取為浮點數。

## toolchain

| 鍵 | 預設值 | 意義 |
| --- | --- | --- |
| `sdk_bundle` | `~/.swiftpm/swift-sdks/darwin.artifactbundle` | 來自 `xtool setup` 的 Darwin SDK bundle |
| `sdk` | bundle 中最新的 `iPhoneOS*.sdk` | 明確指定的 SDK 路徑 |
| `swiftly_bin` | `~/.local/share/swiftly/bin` | 加入至 `PATH` 末尾，供 idl 執行的每個工具使用 |
| `cc` / `cxx` / `swiftc` | `clang` / `clang++` / `swiftc` | 編譯器，透過名稱在 `PATH` 中查找，或直接提供路徑 |
| `xtool` | `xtool` | xtool 執行檔（當使用 `builder: xtool` 時需要） |
| `ldid` | `ldid` | ldid 路徑或指令名稱（當目標需要簽署時需要） |
| `jobs` | `0` | 平行編譯工作數（`0` = CPU 核心數） |
| `actool` | `idl-actool` | 資源目錄編譯器（`zig build actool`）；可以是路徑，或是透過 PATH 及位於 `idl` 旁來查找的名稱 |
| `appintents` | `appintentsmetadataprocessor` | App Intents 中繼資料處理器（[re-appintentsmetadataprocessor](https://codeberg.org/viraptor/re-appintentsmetadataprocessor)，與 Xcode 相同的 CLI）；可以是路徑或 PATH 上的名稱。`app_intents` 目標需要此項 |
| `jimpactor_dir` | `$XDG_CONFIG_HOME/Jimpactor` 或 `~/.config/Jimpactor` | Jimpactor 資料目錄，供 `idl devices` 與 `idl install` 使用 |

路徑中的 `~` 會被展開。

## 目標 (targets)

每個目標都是一個映射。目標內的路徑是相對於其 `dir`，且必須保持在該目錄內（不能使用絕對路徑或 `..`）。

### 識別資訊

| 鍵 | 預設值 | 意義 |
| --- | --- | --- |
| `name` | 必填 | 產品名稱、可執行檔名稱以及 Xcode 目標名稱 |
| `bundle_id` | 必填 | `CFBundleIdentifier` |
| `dir` | `.` | 目標目錄，相對於 `idlproj.yml` |
| `builder` | `direct` | `direct`（idl 執行 clang/swiftc）或 `xtool`（idl 執行 `xtool dev build`） |
| `version` | `1.0` | `MARKETING_VERSION` / `CFBundleShortVersionString` |
| `build_number` | `1` | `CURRENT_PROJECT_VERSION` / `CFBundleVersion` |
| `min_ios` | `16.0` | 部署目標、三元組後綴與 `MinimumOSVersion` |

### 來源與編譯

| 鍵 | 預設值 | 意義 |
| --- | --- | --- |
| `sources` | `[Sources]` | 檔案或目錄，遞迴掃描。支援：`.c .m .mm .cc .cpp .cxx .s .S .swift` |
| `arch` | `arm64` | 目標架構 |
| `opt` | `-Os` | C 系列程式碼的優化旗標 |
| `swift_opt` | `-O` | Swift 的優化旗標 |
| `debug_symbols` | `false` | 在 C 系列與 Swift 物件中產生 DWARF |
| `strict` | `false` | 拒絕不支援的資源與 IB 功能，而非僅發出警告或跳過 |
| `swift_version` | `5.0` | 寫入 Xcode 專案 |
| `defines` | `[]` | `NAME` 或 `NAME=VALUE`。兩種形式都會傳給 C 系列程式碼；僅 `NAME` 會傳給 Swift |
| `include_dirs` | `[]` | clang 與 swiftc 的 `-I` |
| `bridging_header` | none | Swift 匯入的 Objective-C 標頭檔（`-import-objc-header`） |
| `quote_include_dirs` | `[]` | `-iquote` 目錄（clang，以及透過 `-Xcc` 的 swiftc）：僅 `#include "..."` 會看到它們，如同 Xcode 的標頭映射 |
| `framework_dirs` | `[]` | clang、swiftc 與連結器的 `-F` 目錄 |
| `dead_strip` | `true` | 傳給連結器 `-dead_strip` |
| `cflags` / `swiftflags` | `[]` |額外的編譯器旗標 |
| `ldflags` | `[]` | 額外的連結器參數，每個都以 `-Xlinker <arg>` 傳遞 |
| `frameworks` | `[UIKit, Foundation]` | SDK 框架（`X` 或 `X.framework`） |
| `weak_frameworks` | `[]` | 弱連結的框架 |
| `libraries` | `[]` | `-l` 函式庫，例如 `[z, sqlite3]` |
| `build_dir` | `build` | 物件、應用程式套件與 IPA 的位置 |
| `app_intents` | 當 `frameworks` 包含 `AppIntents` 或 `WidgetKit`，或已連結的靜態目標具有 intents 時開啟 | 將 App Intents 中繼資料提取至 `Metadata.appintents`（見下文） |

如果目標有任何 `.swift` 檔案，swiftc 會以單一整個模組編譯所有 Swift 來源，並連結由 clang 編譯的物件。除錯組建會將 Swift 編譯為持久的 `.swift.o` 並單獨連結，保留 DWARF 而無需 `dsymutil`。否則由 clang 進行連結。C++ 來源會加入 `-lc++`。

### 應用程式意圖中繼資料

iOS 會讀取套件（bundle）的 `Metadata.appintents` 來尋找其應用程式意圖：捷徑動作、`AppIntentConfiguration` 小工具設定以及互動式小工具按鈕（`Button(intent:)`）。若缺少此檔案，意圖雖能編譯但無法執行。對於具有 `app_intents` 的目標（應用程式、應用程式擴展或框架），idl 會執行與 Xcode 的「ExtractAppIntentsMetadata」步驟相同的工作：

1. swiftc 會寫入模組的常數值（使用 `-emit-const-values-path`，並將 App Intents 協議列表作為 `-const-gather-protocols-file`）。
2. 連結之後，`toolchain.appintents` 會讀取二進位檔案、來源檔案與常數值（`--compile-time-extraction`），並寫入 `<obj>/appintents/Metadata.appintents`（包含 `extract.actionsdata`、`version.json`）。
3. 該檔案位於套件的根目錄，例如 `PlugIns/Widgets.appex/Metadata.appintents`。

具有 `app_intents` 的靜態（static）目標僅記錄其常數值；每個連結它的套件都會將其靜態模組與自身的常數值一併提取（因此，由應用程式及其小工具擴展共用且必須在應用程式中執行的意圖，例如 `AudioPlaybackIntent`，會位於一個同時被兩者連結的靜態目標中）。連結此類目標會為該套件啟用提取功能。

宣告無任何意圖的模組不會產生中繼資料。預設情況下（WidgetKit/AppIntents 位於 `frameworks`），若缺少處理器會發出警告；若設定 `app_intents: true` 或 `--strict`，則視為錯誤。`app_intents: false` 會關閉此檢查。

WidgetKit 擴展是一種具有 Swift `@main WidgetBundle` 且無 `ldflags` 進入點（entry point）的 `appex`：

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

### 套件

| 鍵 | 預設值 | 意義 |
| --- | --- | --- |
| `info_plist` | none | 可選的基礎 Info.plist（XML、二進位、JSON 或 OpenStep）；否則完全由 YAML 產生 |
| `info` | none | 合併至 Info.plist 的鍵（見下文） |
| `plist_vars` | none | Info.plist 和權限設定的額外 `$(VAR)` 值 |
| `entitlements` | none | 權限鍵的 YAML 映射，或明確的舊版 plist 路徑；不會隱式新增功能 |
| `resources` | `[]` | 複製到套件中的檔案或目錄（見[限制](limitations.md)） |
| `sign` | `direct` 為 `true`，`xtool` 為 `false` | 使用 ldid 進行臨時簽章 / 將 `--sign` 傳遞給 xtool |
| `app_icon` | `AppIcon` | Xcode 專案中的資源目錄圖示名稱 |
| `icon` | none | 僅限 xtool 目標：複製到應用程式根目錄的 PNG，並設為 `CFBundleIconFile`（xtool `iconPath`） |
| `device_family` | `1,2` | 產生的 `UIDeviceFamily` 和 Xcode `TARGETED_DEVICE_FAMILY` |

Info.plist 處理順序如下：

1. 從空字典（或明確的 `info_plist` 基礎）開始。新增任何缺少的標準鍵：`CFBundleExecutable`、
   `CFBundleIdentifier`、
   `CFBundleName`、`CFBundlePackageType`、`CFBundleInfoDictionaryVersion`、
   `CFBundleShortVersionString`、`CFBundleVersion`。此外，顯示名稱預設為目標名稱，開發區域預設為 `en`，`LSRequiresIPhoneOS` 為 true，
   裝置家族為 `device_family`，方向為縱向，且除非已配置啟動故事板，否則 `UILaunchScreen` 為空字典。
2. 合併 `info:` 映射。未加引號的 `true`/`false` 變成布林值，
   未加引號的整數變成 `<integer>`，列表變成陣列，映射變成字典，而加引號的值保持字串。版本鍵如
   `CFBundleVersion` 始終保持字串。
3. 將 `MinimumOSVersion` 設為 `min_ios`。
4. 對於直接建構，合併資源編譯器產生的圖示鍵。
5. 在所有字串中展開 `$(VAR)`、`${VAR}` 和 `$(VAR:modifier)`。值
   來自 `plist_vars`，然後是內建變數，最後是環境變數。
   未知的變數會變成空字串。修飾詞會被忽略。

內建變數：`EXECUTABLE_NAME`、`PRODUCT_NAME`、`TARGET_NAME`、
`PRODUCT_MODULE_NAME`、`PRODUCT_BUNDLE_IDENTIFIER`、
`PRODUCT_BUNDLE_PACKAGE_TYPE`、`MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、
`IPHONEOS_DEPLOYMENT_TARGET`、`DEVELOPMENT_LANGUAGE`。

不需要手寫的 XML：

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

若使用程式化介面，可省略故事板鍵。若不需要功能，可省略 `entitlements`；`get-task-allow` 是選配加入，而非發行預設值。
權限支援與 `info` 相同的 YAML 類型和變數展開。
它們是請求，而非配置設定：Apple 功能仍需要適當的簽章身份/設定檔。明確的 `info_plist` 或字串值的
`entitlements: Support/App.entitlementments` 仍然受支援。缺少明確檔案會視為錯誤，不會靜默忽略。

`idl gen` 和 `idl xcodeproj` 會寫入 `.idl/Info.plist` 以及（若已配置）
每個目標目錄內的 `.idl/Entitlements.plist`。Xcode 和 xtool 參考這些產生的檔案。在 Xcode 中建構前，請執行 `idl gen` 以編輯 YAML。`.idl/debug/` 和 `.idl/release/` 的元資料集也會產生；
Xcode 配置會參考其對應的集合。變數會在產生時使用各設定檔進行展開，而非由 Xcode 從 YAML 重新評估。
直接建構會自行產生套件元資料；xtool 元資料會在每次 xtool 建構前重新產生。`.idl/` 是可丟棄的，應納入 gitignore。

### 產品

| 鍵 | 預設值 | 意義 |
| --- | --- | --- |
| `type` | `app` | `app`、`framework`、`dylib`、`appex`、`static` 或 `test` |
| `link` | `[]` | 專案中需連結的 `framework`/`dylib`/`static` 目標（`test` 目標：僅限 `static`） |
| `embed` | `[]` | 僅限應用程式：需複製到套件中的專案 `framework`/`dylib`/`appex` 目標 |
| `post_build` | `[]` | 僅限應用程式：在 IPA 建立並驗證後依序執行的指令（argv 列表）或指令列表；可透過 `idl build --no-post-build` 跳過 |

`idl build X` 會建立 X 以及它連結或嵌入的所有目標，優先處理相依性。
循環相依會視為錯誤。每種類型產生：

- `framework`：`<build>/products/<name>.framework`（二進位檔、生成的 Info.plist
  包含 `FMWK`、資源），安裝路徑為 `@rpath/<name>.framework/<name>`，套件
  使用 ldid 簽署。相依目標使用 `-F <build>/link -framework <name>` 進行連結。
  應用程式會將其嵌入 `Frameworks/` 下。
- `dylib`：`<build>/products/<name>.dylib`，安裝路徑為 `@rpath/<name>.dylib`，
  嵌入於 `Frameworks/` 下。無 `bundle_id`、Info.plist 或資源。
- `appex`：`<build>/products/<name>.appex`（包含 `XPC!` 的 Info.plist、權限宣告，
  使用 `-I<bundle_id>` 簽署），以 `-fapplication-extension` /
  `-application-extension` 編譯。Rpaths 包含 `@executable_path/../../Frameworks`。
  應用程式會將其嵌入 `PlugIns/` 下。進入點來自 `ldflags`（例如
  `[ -e, _NSExtensionMain ]` 用於主類別的擴充功能，如鍵盤）或
  Swift 的 `@main`（WidgetKit 的 `WidgetBundle`、ExtensionKit）。
- `static`：編譯後的物件加上 `<name>.swiftmodule` 和 `<name>-Swift.h`。一個
  連結目標會在其連結中包含這些物件，使用 `-I` 指定模組路徑，以及標頭目錄。未簽署。無 `bundle_id`。
- `test`：Linux 主機的單元測試，僅由 `idl test` 建立並執行（請參閱
  [tests](#host-test-targets-type-test)）。`idl build` 會跳過它們。

非應用程式目標中的 Swift 以 `-parse-as-library` 編譯，模組名稱為
`<name>`。`post_build` 在目標目錄中執行，並設定 `IDL_IPA`、`IDL_APP`、
`IDL_BUILD_DIR`、`IDL_TARGET`、`IDL`（正在執行的 idl 路徑），以及使用 `-c` 時設定的
`IDL_CONFIGURATION`。若指令以非零狀態碼結束，則視為失敗。

在 `info:` 中，`Key: ~` 會移除從 `info_plist` 繼承的鍵。Info.plist 和
權限宣告展開也可使用專案根目錄 git checkout 中的 `$(GIT_BRANCH)` 和 `$(GIT_COMMIT)`（環境變數會覆蓋它們）。來源和資源項目可在其最後一個路徑元件中使用 `*`，例如
`Resources/*.lproj`。

### 格式化、程式碼檢查與測試 (`idl fmt`, `idl lint`, `idl test`)

idl 僅負責協調這些工具。它會將 YAML 設定轉換為 `.idl/quality/<target>/` 目錄下的格式，因此不需要手動撰寫的 `.clang-format` 或 `.swift-format` 檔案。它會明確傳遞設定、平行執行工具，並將輸出合併為一份去重複的報告：
`file:line:col: severity: message [flag] (tool)`，接著是各工具的摘要以及最常見的旗標/檢查項目。

`format:`（與 `defaults:` 進行合併）：

| Key | Default | Meaning |
| --- | --- | --- |
| `indent` | `4` | 縮排寬度（clang-format `IndentWidth`/`ObjCBlockIndentWidth`、swift-format `indentation.spaces`） |
| `line_length` | `0` | 0 = 永不重新換行（clang-format `ColumnLimit: 0`） |
| `clang_format` | none | 額外的 clang-format 鍵值；它們會覆蓋自動產生的設定（允許巢狀映射） |
| `swift_format` | none | 額外的 swift-format JSON 鍵值，深度合併（例如 `rules:`） |
| `exclude` | `[]` | 永遠不進行格式化的來源路徑或目錄（每個路徑元件使用 `*`） |
| `editor_configs` | `false` | `idl gen` 也會寫入 `.clang-format`、`.clang-tidy` 和 `.swift-format`，供 clangd/sourcekit-lsp 使用 |

`idl fmt [--check] [target...]` 使用 clang-format 格式化 C、Objective-C、C++、Objective-C++ 及標頭檔，並使用 swift-format 格式化 Swift。`--check` 不會修改任何檔案，若有任何檔案會變更則回傳 1。

`lint:`：

| Key | Default | Meaning |
| --- | --- | --- |
| `warnings` | `[-Wall]` | 新增至編譯器階段的 clang 警告旗標 |
| `swift_flags` | `[]` | Swift 類型檢查的額外 swiftc 旗標 |
| `exclude` | `[]` | 不進行程式碼檢查的路徑；位於這些路徑的診斷資訊也會被捨棄 |
| `clang_tidy` | auto | 執行 clang-tidy（auto = 當已安裝時） |
| `clang_tidy_checks` | idl's set | clang-tidy `Checks`；預設為 clang-analyzer、bugprone 和 performance 檢查，排除較吵雜的項目 |
| `analyze` | `false` | 同時執行 clang 靜態分析器（`clang --analyze`） |
| `swift_format` | `false` | 同時使用產生的樣式執行 `swift-format lint` |

`idl lint [target...]` 首先增量式地建構目標及其相依性，以便 Swift 模組和產生的 `<Module>-Swift.h` 標頭檔存在。接著它會以目標的精確建構旗標重新執行每個編譯器。每個 C-family 檔案都會獲得 `clang -fsyntax-only`，移除目標的 `-w`、`-Werror` 和 depfile 旗標，並新增 `lint.warnings`。每個 Swift 模組會獲得 `swiftc -typecheck` 並啟用警告。clang-tidy、靜態分析器和 `swift-format lint` 會共用相同的旗標。來自 SDK、排除路徑的診斷資訊，以及跨翻譯單元重複的相同標頭警告會被捨棄。選項：`--werror`、`--analyze`、`--tidy`/`--no-tidy`、`-q`（僅摘要）和 `--max N`。錯誤會回傳 1，若使用 `--werror`，警告也會回傳 1。

`tests:`（僅限應用程式）是命令列表（argv 列表）。`idl test [target...]`
建構目標但不執行 `post_build`（除非指定 `--no-build`）。接著它會檢查每個應用程式的已建構套件：
- 每個 Mach-O 必須是 arm64、為 iOS 建構，且已簽署。嵌入式程式碼不得要求比應用程式的 MinimumOSVersion 更新的 iOS；擴充功能除外。
- 每個 `@rpath`/`@loader_path`/`@executable_path` 相依性必須在套件內解析，使用影像自身的 rpaths。系統函式庫必須存在於 SDK 中。私有框架和弱連結僅產生警告。
- 每個框架和擴充功能都需要 Info.plist 和可執行檔，並包含字串版本的鍵值。
- 每個擴充功能的 bundle ID 必須以應用程式的為前綴，且必須具有 `NSExtension`/`EXAppExtensionAttributes`。

檢查完成後，`tests:` 中的命令會在目標目錄中執行，並設定 `IDL_IPA`、`IDL_APP`、`IDL_BUILD_DIR`、`IDL_TARGET` 和 `IDL`。

#### 主機測試目標（`type: test`）

iOS 二進位檔案無法在 Linux 上執行，且 iPhoneOS SDK 沒有 XCTest，因此 `type: test` 目標會在 Linux 主機上編譯並執行，同時連結其靜態（static）目標（遞迴地）：

```yaml
  - name: CalcCore            # 被測試的程式碼；也會被應用程式連結
    type: static
    dir: Core
    sources: [Sources]
    frameworks: [Foundation]  # 被測試的程式碼必須支援主機平台
  - name: CalcCoreTests
    type: test
    dir: Tests
    sources: [Sources]        # 測試檔案
    link: [CalcCore]          # 被測試的靜態目標
```

- Swift：idl 會寫入一個 SwiftPM 套件至 `<build_dir>/test/<name>/`（每個被測試的靜態目標對應一個程式庫目標，名稱與之相同，以及一個測試目標），並執行 `swift build --build-tests` 和 `swift test`，其中 `swift` 位於 `toolchain.swiftc` 旁邊。SwiftPM 會發現 XCTest 和 swift-testing 測試；`@testable import CalcCore` 可用。SwiftPM 不接受套件範圍外的目標路徑，且 idl 不會建立符號連結，因此來源檔案會被複製到套件中（僅變更的檔案會被重寫）；編譯器和測試輸出中的路徑會指向原始檔案。每個目標繼承：`swift_version`（語言模式）、不含 `=` 的 `defines`、`include_dirs`、`quote_include_dirs`、`swiftflags`、`libraries` 和 `ldflags`。若未指定 `-c` 或指定 `-c debug`，SwiftPM 會編譯為 debug；`-c release` 則以 `-enable-testing` 編譯為 release。
- C, C++（僅在具有主機執行階段時支援 Objective-C）：主機的 `toolchain.cc`/`cxx` 會編譯測試來源檔案和被測試靜態目標的來源檔案（每個都有各自的 `opt`、`defines`、`include_dirs`、`quote_include_dirs`、`cflags`；測試也會獲得被測試目標的 `include_dirs`）至 `<build_dir>/test/<name>/<name>`，連結 `libraries`/`ldflags`，並在目標目錄中執行它。退出狀態 0 表示通過。與直接編譯一樣支援增量編譯。
- 每個目標一種語言：Swift 測試連結 Swift 靜態目標，C-family 測試連結 C-family 目標。
- `frameworks` 僅可指定 Foundation、FoundationEssentials、FoundationNetworking、FoundationXML、Dispatch、XCTest 或 Testing；測試目標所連結的每個靜態目標也適用相同規則。UIKit 或 SwiftUI 程式碼無法在主機上進行測試。測試目標不會從 `defaults:` 繼承 `frameworks`。
- 測試目標不需要 `bundle_id`。不允許在它們上使用：`builder: xtool`、`xcodeproj`、`post_build`、`tests:`、`embed`、資源、Info.plist、entitlements、`weak_frameworks`、`framework_dirs`、`bridging_header`。沒有任何東西可以 `link` 或 `embed` 測試目標。`configurations:` 和 `-c` 輸出目錄的行為與其他目標相同。
- `idl gen` 會寫入 `compile_commands.json`，包含測試目標的主機旗標（當 `compile_commands: true` 時）。`idl clean` 會移除 `<build_dir>`。`idl lint` 會跳過測試目標；`idl fmt` 會格式化它們。`idl build`、`idl lint`、`idl install` 和 `idl xcodeproj` 會拒絕明確指定的測試目標。

`idl test` 若無目標名稱，則檢查每個應用程式並執行每個測試目標；名稱可選擇應用程式和/或測試目標。`--no-build` 會執行現有的輸出（`swift test --skip-build`，現有的可執行檔案）。

輸出（stdout）每行包含一個應用程式檢查結果、`tests:` 命令和測試目標的結果，然後是摘要；工具輸出和 `==>` 進度行則穿插其間：

```
PASS <app> bundle checks
FAIL <app> bundle checks (<n> error(s))   # 或 "(error)": 套件遺失/無法讀取
PASS <app>: <command and arguments>
FAIL <app>: <command and arguments>
PASS <test target> tests
FAIL <test target> tests (build failed)
FAIL <test target> tests (exit code <n>)
FAIL <test target> tests (error)          # 組態或工具遺失；訊息在 stderr 上

<passed> passed, <failed> failed
```

退出狀態：若全部通過則為 0，若有任何失敗（stderr 以 `error: tests failed` 結尾）或無法載入專案則為 1，使用錯誤則為 2。

工具路徑可在 `toolchain:` 下設定為 `clang_format`、`clang_tidy` 和
`swift_format`（swift-format 隨 swiftly toolchain 提供）。若缺少可選工具，則會跳過並附帶註記。

### 程式碼產生

| 鍵 | 預設值 | 產生 |
| --- | --- | --- |
| `xcodeproj` | `false` | `<dir>/<name>.xcodeproj`（專案 + 共用方案） |
| `compile_commands` | `false` | `<dir>/compile_commands.json`（僅直接目標） |
| `package_swift` | `true` | `<dir>/Package.swift`（僅 xtool 目標） |
| `configuration` | `release` | xtool 建構組態（`debug`/`release`） |

xtool 目標一律會產生 `xtool.yml`。產生的檔案以
`Generated by idl from idlproj.yml` 標記開頭，且 `idl` 拒絕覆蓋沒有該標記的
檔案。若要保留手寫的 `Package.swift`，請設定
`package_swift: false`。

xtool 目標必須恰好有一個 `sources` 條目：SwiftPM 目標
目錄。

## 組態

在 `build`、`install`、
`check`、`gen`、`xcodeproj`、`list` 和 `clean` 上使用 `-c debug` / `--configuration release` 進行選擇：

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

內建偵錯設定：`opt: -O0`、`swift_opt: -Onone`、`debug_symbols: true`，
以及額外的 `DEBUG` 定義。內建發行設定：`-Os`、`-O`，無
DWARF；繼承的 YAML `get-task-allow` 設為 false。設定檔覆寫
可明確變更這些預設值。若應用程式要求無功能，則不會製造權限檔案。對於舊版權限檔案
輸入，如有需要，請在發行設定檔中明確覆寫權限。

優先順序（由低到高）：`defaults` -> 目標 -> 內建設定檔 -> 全域
`configurations.<name>` -> 目標 `configurations.<name>`。對應會遞迴合併，清單取代而非附加，且 `~` 清除可選
值。`DEBUG` 會在偵錯組建合併後附加。

支援的設定檔覆寫：`bundle_id`、`opt`、`swift_opt`、`debug_symbols`、
`defines`、`info`、`entitlements`、`plist_vars`、`build_dir`、`cflags`、
`swiftflags`、`ldflags`、`strict`、`sign`。目標、來源清單和相依性
不依賴設定檔。未知的設定檔名稱/鍵會視為錯誤。

設定檔輸出路徑為 `<build_dir>/debug/` 和 `<build_dir>/release/`，
適用於兩種建構器（xtool 的 IPA 會複製到該設定檔路徑）。Xcode 接收
匹配的優化、定義、偵錯符號、簽章和中繼資料設定。
若無 `-c`，則保留舊版旗標和輸出路徑；舊的目標
`configuration:` 鍵仍選擇 xtool 的底層組態。

## 預設值

`defaults:` 接受任何目標鍵，除了 `name`、`dir` 和 `bundle_id`。一
個目標會遞迴覆寫預設值的對應（`info`、`entitlements` 等）；
清單會被取代，不會合併，且 `~` 會清除可選的對應/值。

## 完整範例

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
