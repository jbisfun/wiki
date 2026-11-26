# 已知限制

## 簽署與安裝

- 簽章為臨時的 `ldid` 簽章。它們使套件結構完整，但並非 Apple 的配發（provisioning）格式。安裝前請重新簽署。
- 此工具鏈尚未在此處建構的 IPA 已在裝置上安裝或執行。檢查是結構性的：ZIP、plist 與 Mach-O 載入命令。
- xtool 目標未簽署，除非 `sign: true`，這會將 `--sign` 傳遞給 xtool，並需要 xtool 登入。

## 僅限 Xcode 的建構步驟

這些工具在此處沒有 Linux 替代品。寬鬆模式（permissive）建構會發出警告並跳過其輸入；`--strict` 則在應用程式編譯前拒絕它們：

- Core Data 模型（`.xcdatamodeld`、`momc`）。
- Metal 著色器（`.metal`）列於產生的 Xcode 專案中，但未被 `direct` 建構所編譯。

App Intents 的元資料需要外部處理器（`toolchain.appintents`、re-appintentsmetadataprocessor）。連結至 `static` 目標的 Intents 會提取到每個連結它們的套件中；`framework` 目標擁有自己的 `Metadata.appintents`，但相依項目不會參照它（`--metadata-file-list`）。App Shortcuts 的片語本地化（`.stringsdata`）尚未產生。

字串目錄（`.xcstrings`）、故事板、XIB 與資產目錄在 Linux 上編譯，限制如下。

## 故事板與 XIB（`idl ibtool`）

編譯器是 [davidquesada/ibtool](https://github.com/davidquesada/ibtool) 的 Zig 移植版本，這是一個逆向工程的 NIB 寫入器。Apple 的格式未文件化，因此：

- **尚未在裝置上驗證。** 輸出可透過 idl 自身的讀取器解碼，並具有與 Xcode nibs 相同的 NIBArchive 配置，但 `idl` 產生的任何 nib 都尚未由 UIKit 在裝置上載入。依賴前請先測試。
- **UIKit 的子集。** 支援的元件：視圖控制器（純、導航、表格）、`view`、`label`、`button`（每個狀態的標題）、`imageView`、`textView`、`searchBar`、`navigationBar`/`navigationItem`/`barButtonItem`、具有模糊/飽和度的 `visualEffectView`、具有原型儲存格、框架、自動調整大小遮罩、顏色、字型、約束、連接埠、動作與轉場（`show`、`showDetail`、`presentation`、`push`、`modal`、`replace`、`custom`，以及 `rootViewController` 關係）的 `tableView`。`textField`、`switch`、`slider`、`scrollView`、`activityIndicatorView` 與 `progressView` 獲得其類別、框架與顏色，但沒有它們自己的屬性。其他任何內容（堆疊視圖、集合視圖、標籤列控制器、影像、手勢識別器、使用者定義的執行階段屬性、特質變化、本地化）會被跳過，寬鬆建構會發出診斷訊息；嚴格建構會在應用程式編譯前拒絕不支援的節點與屬性。
- **安全區域佈局指南** 被視為擁有它們的視圖，因此對安全區域的約束會固定到視圖的邊緣。
- 參照不支援物件的約束會被捨棄並發出警告。
- 命名顏色（`systemColor` / `name`）透過文件自身的 `<resources>` 區段解析，因此變成固定顏色且不跟隨深色模式。文字樣式變成固定大小的系統字型。
- 僅限 iOS 文件（`targetRuntime="iOS.CocoaTouch"`）。每個文件為每個視圖控制器與視圖產生一個 nib；沒有每裝置類型的變體。

## 資產目錄（`.xcassets`、AssetKit）

資產目錄由 `idl-actool` 編譯，這是 [xtool-org/AssetKit](https://github.com/xtool-org/AssetKit) 的小型 Swift 包裝函式。由於 AssetKit 是一個 Swift 程式庫，因此它是獨立的二進位檔案。

- 使用 `zig build actool` 建置。這需要 PATH 中有 `swift`。預設情況下，它使用工具鏈的共用 Swift 執行階段（在此約為 1.2 MB）。Swift 會嵌入一個指向該工具鏈的執行階段搜尋路徑：如果您移除它，請重新建置 `idl-actool`。使用 `zig build actool -Dactool-static=true` 可獲得獨立的 Swift 執行階段（在此約為 59 MB）。xtool 私有的嵌入式執行階段無法與其他可執行檔共用。
- 僅支援 AssetKit 所支援的影像集、色彩集和一個應用程式圖示。資料集、符號集、Sprite 精靈圖集、按需資源標籤和具名應用程式圖示替代方案則不支援。
- 應用程式圖示需要每個影像明確的 `scale`，例如 iPhone 的 `60x60` @2x 和 @3x。Xcode 單一的 1024 pt「通用」圖示沒有比例，AssetKit 會拒絕它。`app_icon` 設定不會傳遞下去：AssetKit 會使用目錄中所擁有的任何 `.appiconset`。
- 每個目標一個 `.xcassets`。如果您有多個，請合併目錄。
- SVG 影像需要 PATH 中有 `rsvg-convert`（librsvg）。
- 目錄、故事板、XIB 和字串會根據輸入內容和編譯器身分進行快取。直接目標的捆綁/簽署/封裝也會跳過未變更的輸出。

## 專案模型

- `direct` 目標可以是應用程式、動態程式庫、dylibs、應用程式延伸模組或靜態（物件 + Swift 模組）目標；請參閱設定參考中的「產品」。僅應用程式會進行封裝；其他種類是為應用程式的 `link`/`embed` 清單所建置。不支援 Watch 應用程式、測試套件、XCFrameworks 和真正的 `.a` 封存檔，產生的 Xcode 專案和 xtool 建構器僅處理應用程式目標。預先建置的 `.framework` 資源會複製到 `Frameworks/`（不含 Headers、Modules 或 _CodeSignature）並進行臨時簽署，且 `@executable_path/Frameworks` 始終是一個 rpath。
- 支援偵錯/發行設定檔。不支援任意其他設定檔和設定檔相依的來源/相依圖表。省略 `-c` 會保留舊版未設定檔的旗標/輸出路徑。
- 偵錯符號保留在物件檔案中；不會產生 `.dSYM` 封存/匯出。
- C 家族的增量編譯仍基於 mtime/depfile；內容基礎快取適用於資源和最終捆綁/IPA 狀態。這是本機快取，並非跨機器的封閉/可重現建構保證。
- 資源會像 Xcode 一樣展平到捆綁根目錄中，但 `*.lproj/` 資料夾和套件目錄（`.bundle`、`.framework`、`.mlmodelc`）會保留。兩個具有相同檔案名稱的資源會產生錯誤。產生相同語言檔案的 `.xcstrings` 檔案和 `.lproj/Localizable.strings` 資源會發生衝突。
- Swift 使用全模組編譯，因此變更 Swift 來源會重新編譯目標中的所有 Swift。偵錯編譯和連結是獨立的步驟。
- Swift 在目標的 C 家族來源之前編譯。如果目標混合了它們，idl 會產生 `<Module>-Swift.h` 並將其放在包含路徑上，以便 Objective-C 可以 `#import "<Name>-Swift.h"`。Swift 透過 `bridging_header` 呼叫 Objective-C。
- Swift `defines` 必須是純旗標。`NAME=VALUE` 僅適用於 C 家族程式碼。
- 僅測試 `arm64` 裝置建構。沒有模擬器 SDK。

## xtool 建構器

- xtool 目標會將 `resources:` 傳遞至 xtool.yml，並將其原樣複製到應用程式根目錄（`.lproj` 資料夾、純檔案）。需要編譯器的資源（`.xcassets`、故事板、XIB、`.xcstrings`、Core Data、Metal、Core ML）會被拒絕；請對這些使用 `builder: direct`。xtool 會管理其自身的建構與封裝快取。

- SwiftPM 無法在同一個目標中混合 Swift 和 C 系列檔案，因此 xtool 目標要麼全是 Swift，要麼全是 C/Objective-C。對於混合程式碼，請使用 `builder: direct`。
- 具有 Objective-C 的 xtool 目標，其 `main()` 檔案的名稱不能是 `main.m`：SwiftPM 會將其視為可執行目標。範例使用的是
  `appmain.m`。
- 產生的 `Package.swift` 有一個程式庫目標。對於更複雜的情況，請自行撰寫並設定 `package_swift: false`。

## 工具鏈

- `idl-actool` 必須支援 `--version`；當升級 idl 至其輔助程式缺乏該命令的版本時，請使用 `zig build actool` 重新建構它。
- xtool 的權限重寫路徑可能會遺漏可執行 ZIP 的權限位元。idl 會正規化主要可執行檔案的 ZIP 中繼資料，而不改變其程式碼
  位元組或簽章，然後執行正常的 IPA 驗證。

- xtool 的 `ld64.lld` 會列印 `This version of lld does not support linking for platform iOS`。輸出是正確的：Mach-O 具有 `LC_BUILD_VERSION`
  平台 iOS。`idl verify` 會檢查此項。
- 檔案和標頭路徑在 Linux 上是區分大小寫的，這與預設的 macOS 磁碟區不同。
- `idl` 不會安裝或下載工具。請自行安裝 Swift 工具鏈、Darwin SDK、ldid 和 xtool。`idl check` 會列出缺少的項目。
  `idl-actool` 是透過此儲存庫使用 `zig build actool` 建構的。

## 設定解析（zig-yaml）

`idl` 使用設定檔案所需的 YAML 子集。該函式庫的已知問題：

- 具有空值的金鑰後接兄弟金鑰（`key:` 然後
  `other: x`）會被解析為巢狀映射。請寫成 `key: ~` 或省略該金鑰。
- 註解和尾隨空白會在解析前移除，因此
  `key: value  # note` 可以運作。引號內的 `#` 或前面沒有空白的 `#`（`url: http://x/#frag`）會被保留。支援多行引號字串和區塊標量（`|`, `>`）。
- 不支援錨點、別名和標籤。

## 封裝

- IPA 寫入器不支援 ZIP64，因此 IPA 及其中的每個檔案必須小於 4 GiB。時間戳記固定為 1980-01-01，以便輸出具有可重複性。
- 來源、資源、套件目錄和 Xcode 專案輸出中的符號連結會被拒絕，且不會寫入 IPA 中。
