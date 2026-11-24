# 架構

`idl` 是單一的 Zig 執行檔（libplist 已編譯進去；只以動態方式連結 libc）。它讀取 `idlproj.yml`，然後
產生檔案或執行外部編譯器。它不包含
通用的工作語言：它追蹤編譯器相依關係、準備
經過衝突檢查的資源計畫，並快取資源與 bundle 的輸出。

```
idlproj.yml ──► config ──► codegen ─► .xcodeproj, xtool.yml, Package.swift, compile_commands.json
                  │
                  └──► builder ─► clang / clang++ / swiftc ─► ld64.lld (xtool SDK)
                         │            (parallel, incremental)
                         ├─► plist (libplist): Info.plist, entitlements
                         ├─► resources: xcstrings, ibtool (storyboard/xib ─► nib),
                         │              idl-actool (xcassets ─► Assets.car)
                         ├─► ldid (from PATH or toolchain.ldid)
                         ├─► zip writer ─► .ipa
                         └─► verify: zip reader + plist + Mach-O parser
```

## 原始碼對照

| 檔案 | 職責 |
| --- | --- |
| `src/main.zig` | CLI：zig-clap 頂層命令，加上每個子命令各自的解析器 |
| `src/config.zig` | `idlproj.yml` 結構描述、合併 `defaults`、驗證、向上搜尋檔案 |
| `src/ynode.zig` | 建立在 zig-yaml 解析樹上的無損 YAML 檢視（保留純量文字；移除註解） |
| `src/toolchain.zig` | SDK／編譯器／ldid 探索、編譯器與連結器旗標組合、`idl check` |
| `src/resources.zig` | 資源快取、嚴格驗證、輸出衝突計畫，以及 storyboard／nib 參照檢查 |
| `src/buildstate.zig` | SHA-256 目錄樹指紋、快取記錄／輸出完整性，以及每個資料夾的 OS 鎖 |
| `src/builder.zig` | 平行增量編譯、連結、bundle 組裝、簽署、封裝、xtool 執行、清除 |
| `src/codegen.zig` | `xtool.yml`、`Package.swift`、`compile_commands.json`，以及防止覆寫非產生檔案的保護 |
| `src/pbxproj.zig` | 具確定性的 Xcode 專案與 scheme；原子性、防符號連結的發佈 |
| `src/metadata.zig` | 由 YAML 驅動的 Info.plist 與 entitlements，供直接建置、Xcode 與 xtool 建置共用 |
| `src/plist.zig` | libplist 包裝層、Xcode `$(VAR)` 展開、CLI 值解析 |
| `src/xcstrings.zig` | 將 String Catalog 轉為 `.strings` / `.stringsdict` |
| `src/zip.zig` | 具確定性的 ZIP 寫入器（std.compress.flate）與會檢查 CRC 的讀取器 |
| `src/macho.zig` | Mach-O 標頭與載入命令檢查 |
| `src/verify.zig` | `build` 與 `verify` 使用的 IPA 驗證 |
| `src/ibtool.zig` | 將 `.xib` / `.storyboard` 轉為 nib 物件圖（移植自 davidquesada/ibtool） |
| `src/nib.zig` | NIBArchive 物件模型、編碼器與解碼器（`idl ibtool --dump`） |
| `src/xmldom.zig` | 建立在 zig-xml 串流讀取器上的小型 DOM |
| `tools/idl-actool` | AssetKit 的 Swift 包裝層；獨立的執行檔，由 `zig build actool` 建置 |
| `src/jimpactor.zig` | Jimpactor 本機 IPC 協定 v1 的用戶端（`devices`、`install`） |
| `src/scaffold.zig` | `idl init`（原始碼由 `build.zig` 從 `examples/` 內嵌） |
| `src/fsutil.zig` | 與 Xcode 共用的探索規則、路徑驗證、符號連結檢查 |
| `src/diag.zig` | 唯一面向使用者的錯誤訊息通道 |

## 相依套件

所有相依套件都已在 `build.zig.zon` 中固定版本：

- **zig-clap**：引數解析與說明文字。
- **zig-yaml**：YAML 詞法分析器與解析器。`idl` 直接走訪它的 `Tree`，
  而不使用 `Yaml.parse`，因為具型別的解析器會將 `16.10` 強制轉換成
  浮點數，並丟失引號。
- **libplist**（libimobiledevice）：讀寫 XML、二進位、JSON 與
  OpenStep 格式的 plist。它以 `git+https://…#2.8.1`（固定在某個 commit）取得，
  並由 `build.zig` 中的 `buildLibplist` 以 C 原始碼編譯，而不使用其
  autotools 建置。只建置 C 核心，不建置 libplist++。
- **zig-xml**（ianprime0509）：用於 Interface Builder 文件的 XML 讀取器。
  固定在最後一個支援 Zig 0.14 的 commit。
- **AssetKit**（xtool-org）：將 `.xcassets` 轉為 `Assets.car`，僅供
  `tools/idl-actool` 使用（Swift 套件，固定在 1.0.0）。它不會連結進
  `idl`。
- **Zig std**：deflate、CRC-32、SHA-1、JSON 與行程。除了連到 127.0.0.1 上的 Jimpactor 之外，`idl` 不會發出
  任何網路請求。

## 設計筆記

- **確定性的程式碼產生。** Xcode 物件 ID 為
  `SHA1("pbxprojgen:<section>:<key>")[0..12]`，因此相同的輸入永遠產生
  相同的 `project.pbxproj`。底層 ID 與早期的
  Python 產生器保持相容；特定設定檔的設定則刻意擴充了輸出。
- **安全發佈。** 新的 `.xcodeproj` 會寫入私有的同層
  資料夾，再以相對於資料夾 FD、不跟隨符號連結的
  操作（`fstatat(AT_SYMLINK_NOFOLLOW)`、`openat(O_NOFOLLOW)`、
  `renameat`）移到定位。因此，在最後一刻被換入的符號連結無法
  重新導向寫入。單元測試涵蓋了這一點。
- **絕不覆寫手寫檔案。** 產生的原始碼樹檔案帶有
  標記，沒有標記的檔案則不會被動到。
- **編譯前先預檢。** 在任何資源編譯器執行之前，會先探測所有選定的工具；
  在應用程式編譯開始之前，會先準備所有資源計畫。嚴格模式會拒絕不支援或遺漏的輸入。
- **增量建置。** 每個物件檔都有 `.cmd` 命令／工具指紋，
  而 clang 的 `-MMD` depfile 會列出標頭檔。資源使用 SHA-256 內容定址的
  快取項目，並在命中時驗證其輸出樹。打包／簽署／ZIP 僅在
  輸入指紋以及 payload 與 IPA 的完整性都相符時才會略過。
- **鎖定。** Build／check／gen／clean 會在 `.idl/build.lock` 中持有 OS 建議性鎖。
  清除時絕不會 unlink 鎖定檔；關閉描述子即釋放
  鎖。建置會在修改輸出之前取得所有選定的鎖。
- **設定檔產生。** YAML 對應表會深度合併成解析後的 debug／release
  目標。每個設定檔的中繼資料寫在 `.idl/<profile>/` 之下；Xcode 會取得
  兩個設定檔，而 xtool 的資訊清單則描述選定的設定檔。
- **可重現的 IPA。** 項目會排序、時間戳記固定，且 Unix
  模式會保留。只有在能讓項目變小時才使用 Deflate。
- **限定範圍的環境。** swiftly 的 bin 資料夾會附加在 `PATH` 之後，而非
  放在前面，而且只用於傳給子行程的環境。主機
  工具保有優先權。
