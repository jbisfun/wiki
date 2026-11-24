# 已知限制

## 簽署與安裝

- 簽章是 ad-hoc `ldid` 簽章。它們讓 bundle 在結構上完整，但並非 Apple 的佈建（provisioning）。安裝前請重新簽署。
- 此工具尚未將本處建置的任何 IPA 安裝或執行於裝置上。檢查僅限於結構層面：ZIP、plist 與 Mach-O 載入指令。
- xtool 目標除非設定 `sign: true`，否則不會簽署；該設定會將 `--sign` 傳給 xtool，且需要登入 xtool。

## 僅限 Xcode 的建置步驟

這些工具在 Linux 上沒有對應的替代品。寬鬆建置會發出警告並略過其輸入；`--strict` 則會在應用程式編譯前拒絕它們：

- Core Data 模型（`.xcdatamodeld`、`momc`）。
- Metal 著色器（`.metal`）會列在產生的 Xcode 專案中，但 `direct` 建置不會編譯它們。

App Intents 中繼資料需要外部處理器（`toolchain.appintents`，即 re-appintentsmetadataprocessor）。所連結 `static` 目標中的 intent 會被擷取到每個連結它們的 bundle 中；`framework` 目標會帶有自己的 `Metadata.appintents`，但相依者不會參照它（`--metadata-file-list`）。App Shortcuts 片語的在地化（`.stringsdata`）不會產生。

字串目錄（`.xcstrings`）、storyboard、XIB 與資產目錄都能在 Linux 上編譯，但有下列限制。

## Storyboard 與 XIB（`idl ibtool`）

此編譯器是 [davidquesada/ibtool](https://github.com/davidquesada/ibtool) 的 Zig 移植版，後者是經逆向工程的 NIB 寫入器。Apple 的格式沒有公開文件，因此：

- **尚未在裝置上驗證。** 輸出可由 idl 自己的讀取器解碼，且具有與 Xcode 的 nib 相同的 NIBArchive 版面配置，但尚無任何由 `idl` 產生的 nib 曾在裝置上被 UIKit 載入。在依賴它之前請先測試。
- **僅支援 UIKit 的子集。** 支援的元素：檢視控制器（一般、導覽、表格）、`view`、`label`、`button`（依狀態設定標題）、`imageView`、`textView`、`searchBar`、`navigationBar`/`navigationItem`/`barButtonItem`、具有模糊/鮮明效果的 `visualEffectView`、含原型儲存格的 `tableView`、frame、自動調整大小遮罩、顏色、字型、限制條件、outlet、action 與 segue（`show`、`showDetail`、`presentation`、`push`、`modal`、`replace`、`custom`，以及 `rootViewController` 關聯）。`textField`、`switch`、`slider`、`scrollView`、`activityIndicatorView` 與 `progressView` 只會取得其類別、frame 與顏色，不會有各自的屬性。其他任何項目（堆疊檢視、集合檢視、分頁列控制器、影像、手勢辨識器、使用者定義的執行階段屬性、特徵變化、在地化）在寬鬆建置中會被略過並附上診斷訊息；嚴格建置則會在應用程式編譯前拒絕不支援的節點與屬性。
- **安全區域版面配置指南**會被視為擁有它們的檢視，因此指向安全區域的限制條件會改為固定在該檢視的邊緣。
- 參照到不支援物件的限制條件會被捨棄並發出警告。
- 具名顏色（`systemColor` / `name`）透過文件自身的 `<resources>` 區段解析，因此會變成固定顏色，不會跟隨深色模式。文字樣式會變成固定大小的系統字型。
- 僅支援 iOS 文件（`targetRuntime="iOS.CocoaTouch"`）。每份文件會為每個檢視控制器與檢視各產生一個 nib；沒有依裝置慣用語區分的變體。

## 資產目錄（`.xcassets`、AssetKit）

資產目錄由 `idl-actool` 編譯，它是包裝 [xtool-org/AssetKit](https://github.com/xtool-org/AssetKit) 的小型 Swift 封裝程式。因為 AssetKit 是 Swift 函式庫，所以它是獨立的二進位檔。

- 以 `zig build actool` 建置。這需要 PATH 上有 `swift`。預設會使用工具鏈共用的 Swift 執行階段（此處約 1.2 MB）。Swift 會內嵌指向該工具鏈的執行階段搜尋路徑：若你移除了它，請重新建置 `idl-actool`。使用 `zig build actool -Dactool-static=true` 可取得獨立的 Swift 執行階段（此處約 59 MB）。xtool 私有的內嵌執行階段無法與其他可執行檔共用。
- 僅支援影像集、顏色集與一個應用程式圖示，且以 AssetKit 所支援的範圍為限。資料集、符號集、sprite atlas、隨選資源標籤與具名的替代應用程式圖示皆不支援。
- 應用程式圖示的每張影像都需要明確的 `scale`，例如 iPhone 的 `60x60` @2x 與 @3x。Xcode 單一的 1024 pt「universal」圖示沒有 scale，AssetKit 會拒絕它。`app_icon` 設定不會被傳遞：AssetKit 會使用目錄中既有的任一個 `.appiconset`。
- 每個目標僅能有一個 `.xcassets`。若有多個，請合併目錄。
- SVG 影像需要 PATH 上有 `rsvg-convert`（librsvg）。
- 目錄、storyboard、XIB 與字串會依輸入內容與編譯器身分進行快取。direct 目標的打包／簽署／封裝也會略過未變更的輸出。

## 專案模型

- `direct` 目標可以是應用程式、動態 framework、dylib、應用程式擴充功能或 static（物件 + Swift 模組）目標；請參閱設定參考中的「Products」。只有應用程式會被封裝；其他種類是為了應用程式的 `link`/`embed` 清單而建置。Watch 應用程式、測試 bundle、XCFramework 與真正的 `.a` 封存檔皆不支援，而且產生的 Xcode 專案與 xtool 建置器只處理應用程式目標。預先建置的 `.framework` 資源會被複製到 `Frameworks/`（不含 Headers、Modules 或 _CodeSignature）並以 ad-hoc 方式簽署，而 `@executable_path/Frameworks` 一律是 rpath。
- 支援 debug/release 設定檔。任意額外的設定，以及隨設定檔而異的來源／相依圖，則不支援。省略 `-c` 會保留舊版未使用設定檔的旗標／輸出路徑。
- 除錯符號會留在物件檔中；不會產生 `.dSYM` 封存檔／匯出。
- C 系列的增量編譯仍以 mtime／depfile 為基礎；以內容為基礎的快取適用於資源以及最終的 bundle／IPA 狀態。這是本機快取，並不保證跨機器的封閉式／可重現建置。
- 資源會像 Xcode 一樣被攤平到 bundle 根目錄，但 `*.lproj/` 資料夾與套件目錄（`.bundle`、`.framework`、`.mlmodelc`）會被保留。兩個檔名相同的資源會造成錯誤。產生相同語言檔案的 `.xcstrings` 檔與 `.lproj/Localizable.strings` 資源會發生衝突。
- Swift 使用整個模組編譯，因此變更任一 Swift 來源會重新編譯目標中的所有 Swift。除錯編譯與連結是分開的步驟。
- Swift 會先於目標的 C 系列來源編譯。若目標混用兩者，idl 會產生 `<Module>-Swift.h` 並將其放入 include 路徑，因此 Objective-C 可以 `#import "<Name>-Swift.h"`。Swift 則透過 `bridging_header` 呼叫 Objective-C。
- Swift 的 `defines` 必須是單純的旗標。`NAME=VALUE` 僅適用於 C 系列程式碼。
- 僅測試過 `arm64` 裝置建置。沒有模擬器 SDK。

## xtool 建置器

- xtool 目標會將 `resources:` 傳給 xtool.yml，後者會將它們原樣複製到應用程式根目錄（`.lproj` 資料夾、一般檔案）。需要編譯器處理的資源（`.xcassets`、storyboard、XIB、`.xcstrings`、Core Data、Metal、Core ML）會被拒絕；這類資源請使用 `builder: direct`。xtool 自行管理其建置與封裝快取。

- SwiftPM 無法在同一個目標中混用 Swift 與 C 系列檔案，因此 xtool 目標若非全為 Swift，就是全為 C/Objective-C。混合程式碼請使用 `builder: direct`。
- 含有 Objective-C 的 xtool 目標不得將其 `main()` 檔案命名為 `main.m`：SwiftPM 會將它視為可執行目標。範例使用 `appmain.m`。
- 產生的 `Package.swift` 只有一個函式庫目標。若需求更複雜，請自行撰寫並設定 `package_swift: false`。

## 工具鏈

- `idl-actool` 必須支援 `--version`；從其輔助程式缺少該指令的版本升級 idl 時，請以 `zig build actool` 重新建置它。
- xtool 的 entitlement 改寫路徑可能會遺失可執行檔的 ZIP 權限位元。idl 會在不變更其程式碼位元組或簽章的情況下正規化主要可執行檔的 ZIP 中繼資料，然後執行一般的 IPA 驗證。

- xtool 的 `ld64.lld` 會印出 `This version of lld does not support linking for
  platform iOS`。輸出是正確的：該 Mach-O 具有 `LC_BUILD_VERSION` 平台 iOS。`idl verify` 會檢查這一點。
- 在 Linux 上，檔案與標頭路徑區分大小寫，這與預設的 macOS 磁碟區不同。
- `idl` 不會安裝或下載工具。請自行安裝 Swift 工具鏈、Darwin SDK、ldid 與 xtool。`idl check` 會列出缺少的項目。`idl-actool` 由本儲存庫以 `zig build actool` 建置。

## 設定解析（zig-yaml 0.1.x）

`idl` 使用設定檔所需的 YAML 子集。該函式庫的已知問題：

- 值為空的鍵後面接著同層的鍵（`key:` 然後 `other: x`）會被解析為巢狀對應。請寫成 `key: ~` 或省略該鍵。
- 註解與結尾空白會在解析前移除，因此 `key: value  # note` 可正常運作。引號內的 `#`，或前面沒有空白的 `#`（`url: http://x/#frag`）會被保留。不支援多行引號字串與區塊純量（`|`、`>`）。
- 不支援錨點、別名與標籤。

## 封裝

- IPA 寫入器不支援 ZIP64，因此 IPA 與其中每個檔案都必須小於 4 GiB。時間戳記固定為 1980-01-01，使輸出可重現。
- 來源、資源、套件目錄與 Xcode 專案輸出中的符號連結會被拒絕，且絕不會寫入 IPA。
