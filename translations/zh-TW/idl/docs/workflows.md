# 常見工作流程

所有命令都接受 `--help`，例如 `idl build --help`。

## 建置，之後只重建有變更的部分

    idl build              # every target
    idl build MyApp -j 8   # one target, 8 parallel compile jobs
    idl -v build           # print every command (or: idl build -v)

C 系列的物件檔會重用 clang 的 `.d` 標頭相依關係、輸入的 mtime，以及記錄在
`<object>.cmd` 中的命令／工具版本指紋。當連結的
輸入或命令／工具指紋變更時，會重新執行連結。

對於直接目標，已編譯的資源使用 SHA-256 內容指紋，
包含資料夾成員、部署目標、嚴格程度、idl 以及外部
資源編譯器的身分。大小相同但保留 mtime 的編輯、新增、
刪除，以及編譯器版本變更，都會使快取失效。快取輸出的
內容也會被檢查：遺失或損毀的檔案會被重建。

如果執行檔、資源輸出、產生的中繼資料、entitlements 與簽署者
都沒有變更，則會重用 bundle、簽章與 IPA。否則會在 `Payload.partial` 中組裝新的 payload，
簽署並封裝；已刪除的資源不會殘留。`idl build -v` 會回報快取命中。`idl clean MyApp -c debug` 會清除該
設定檔的產出物／快取。舊的內容定址資源項目會保留到
清除為止。xtool 仍會自行管理其增量建置與封裝。

## 嚴格預檢與建置設定檔

    idl check --strict -c release MyApp  # tools + inputs + resources, no app compile
    idl build --strict -c debug MyApp
    idl build --strict -c release --gen
    idl install "My iPhone" -c debug MyApp
    idl gen -c debug MyApp

在編譯任何應用程式原始碼之前，idl 會檢查*所有選定目標*的工具、執行編譯器／輔助工具的版本探測（包含 `idl-actool`，
因此缺少共用執行階段函式庫的情況會被發現）、處理中繼資料、準備
資源，並檢查其完整的 bundle 輸出計畫。因此，後面某個有問題的目標
不會導致較前面的目標先被編譯。資源
準備可能會執行資源編譯器，並在 `idl check` 期間填入快取。
不會安裝或下載任何東西。

`--strict`（或 YAML 中的 `strict: true`）會拒絕不支援的 IB 元素／屬性、
未解析的參照與編譯器警告；不支援的 Core Data、Metal 與
Core ML 輸入；以及不支援的資源套件類型。遺漏的 storyboard／nib
資源（包含 scene-manifest 參照）、重複的產生／原始輸出、
保留輸出衝突，以及不一致的 bundle 身分一律會失敗。
寬鬆模式會診斷不支援的輸入，而不是默默忽略。
嚴格模式並不保證 UIKit 執行階段相容性，也不會消除已記載的
safe-area／顏色近似。

建置、預檢、專案產生與清除會在
`<target>/.idl/build.lock` 持有非阻塞的 OS 鎖。衝突時會以 `build directory busy` 訊息失敗；
沒有需要移除的過期 PID 檔。此鎖是針對每個目標資料夾、跨
設定檔，因為 xtool 與產生的專案檔案共用路徑。作業執行期間請勿刪除
`.idl/`。不同的目標資料夾可以同時
建置。設定檔合併與輸出路徑請見 [configuration](configuration.md#configurations)。

## 重新產生專案檔

    idl gen                # all targets
    idl gen MyApp
    idl build --gen        # regenerate, then build

`gen` 會寫出目標所要求的任何內容：`.xcodeproj`、
`compile_commands.json`，而對於 xtool 目標則包含 `xtool.yml` 與 `Package.swift`。
輸出具確定性，因此執行兩次會得到相同的檔案，
版本控制的差異只會顯示真正的變更。

若要將單一 Xcode 專案寫到其他位置：

    idl xcodeproj MyApp --output /tmp/MyApp.xcodeproj

產生的專案使用相對於專案位置的路徑，並帶有
共用 scheme，因此可以直接在 Mac 上的 Xcode 開啟。

## Linux 上的編輯器支援

設定 `compile_commands: true`（若要套用到所有目標，請放在 `defaults:` 下），然後
執行 `idl gen`。clangd 會從目標資料夾讀取 `compile_commands.json`，
而 Swift 項目則包含供 sourcekit-lsp 使用的完整 swiftc 命令。請先執行一次 `idl build`，讓 `build/ModuleCache` 存在。

## 在既有的 idlproj.yml 中新增應用程式

```yaml
targets:
  - name: Second
    dir: apps/second
    bundle_id: com.example.second
    sources: [Sources]
    entitlements:
      get-task-allow: true
```

若要取得起始檔案，請執行 `idl init Second --dir apps/second`，然後將
其目標項目移到你的主要 `idlproj.yml` 中。

## 混用 Swift、Objective-C 與 C++

```yaml
sources: [Sources]                 # .swift, .m, .mm, .cpp all together
bridging_header: Sources/Bridge.h  # Objective-C declarations Swift can see
include_dirs: [Sources]
```

clang 會將每個 C 系列檔案編譯成物件檔。接著 swiftc 會將所有 Swift
檔案編譯成一個模組並連結這些物件檔。C++ 會加上 `-lc++`。

## 每次建置的 Info.plist 值

```yaml
plist_vars:
  ENV_NAME: staging
info:
  CFBundleDisplayName: MyApp $(ENV_NAME)
```

若某個值在不同機器或 CI 執行之間會有差異，請直接參照
環境變數：未知的 `$(VAR)` 會退而使用行程的
環境。

## Storyboard、XIB 與資源目錄

像其他檔案一樣將它們列為資源。`idl build` 會將它們編譯進
bundle：

| 資源 | Bundle 輸出 | 編譯者 |
| --- | --- | --- |
| `Main.storyboard` | `Main.storyboardc/` | `idl`（ibtool 移植版） |
| `Banner.xib` | `Banner.nib` | `idl`（ibtool 移植版） |
| `Assets.xcassets` | `Assets.car`、App 圖示 PNG、Info.plist 圖示鍵 | `idl-actool`（AssetKit） |

資源目錄需要 `idl-actool`，只需建置一次：

    zig build actool             # installs zig-out/bin/idl-actool next to idl
    zig build actool -p zig-out/release   # if you use the release build

`idl` 會先在 PATH 中尋找 `toolchain.actool`，再找它自己執行檔旁邊。
請將 YAML 中的 `info.UIMainStoryboardFile` / `info.UILaunchStoryboardName` 設為
storyboard 名稱（不含副檔名）。`examples/ib-app` 三者都有使用。

若要編譯或檢視單一檔案：

    idl ibtool Main.storyboard -o /tmp/Main.storyboardc
    idl ibtool Banner.xib --dump          # compile and print the objects
    idl ibtool Some.nib --dump --types    # dump any NIBArchive, even Xcode's

支援範圍請見 [limitations](limitations.md#storyboards-and-xibs-idl-ibtool)。

## 在裝置上安裝（透過 Jimpactor）

`idl` 的 ad-hoc `ldid` 簽章並不是佈建描述檔。在
[Jimpactor](https://github.com/jpdagostin0/jimpactor) 系統匣應用程式執行時，`idl`
可以將 IPA 交給它，由 Jimpactor 使用你的帳號簽署並安裝
這些 IPA：

    idl devices list                   # devices Jimpactor can reach
    idl install "My iPhone"            # build every target, then install each IPA
    idl install 00008130 MyApp         # device by UDID prefix, one target
    idl install 00008130-... --no-build MyApp   # install the last build
    idl install 00008130-... --ipa ~/Downloads/Other.ipa

`<device>` 可以是 UDID、唯一的 UDID 前綴（4 個以上字元），或裝置名稱
（不分大小寫）。`idl` 會在建置之前解析裝置，因此 Jimpactor 未開啟或
裝置未知時會提早失敗。Jimpactor 傳來的安裝進度
會即時印出。

Jimpactor 的 IPC 協定（版本 1）：`idl` 連線到 127.0.0.1，連接埠
位於 `<data>/relaunch.port`，並傳送來自 `<data>/ipc.token` 的權杖。`<data>`
為 `$XDG_CONFIG_HOME/Jimpactor` 或 `~/.config/Jimpactor`，若有設定
`toolchain.jimpactor_dir` 則以其為準。

若沒有 Jimpactor，請使用任何其他工具重新簽署 IPA（AltStore、Sideloadly、
`xtool dev build --sign` 等）。

## 從任何地方檢查 IPA

    idl verify Some.ipa --bundle-id com.example.app
    idl verify unsigned.ipa --allow-unsigned

## 獨立的 plist 與字串目錄工具

    idl plist -i Info.plist -o out.plist \
        --var PRODUCT_BUNDLE_IDENTIFIER=com.example.app \
        --set CFBundleVersion=42 --set UIRequiredDeviceCapabilities='["arm64"]' \
        --default LSRequiresIPhoneOS=true --delete NSExampleKey
    idl xcstrings Localizable.xcstrings build/strings   # -> <lang>.lproj/Localizable.strings(dict)

`--set` 與 `--default` 會將 `[..]`、`{..}`、`true`、`false` 與整數視為
JSON（由 libplist 解析）。其他一律視為字串。

## 清除

    idl clean          # direct: build/; xtool: .build .bsp xtool/; plus a generated .xcodeproj
    idl clean MyApp

## 從 zig build 使用

此儲存庫的 `build.zig` 提供了包裝 CLI 的步驟：

    zig build run -- build MyApp
    zig build check
    zig build examples
