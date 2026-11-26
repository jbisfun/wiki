# 架構

`idl` 是一個單一的 Zig 可執行檔（libplist 已編譯為靜態；僅動態連結 libc）。它讀取 `idlproj.yml`，並產生檔案或執行外部編譯器。它不包含通用的任務語言：它追蹤編譯器相依性、準備碰撞檢查的資源計畫，並快取資源與套件輸出。

```
idlproj.yml ──► config ──► codegen ─► .xcodeproj, xtool.yml, Package.swift, compile_commands.json
                  │
                  └──► builder ─► clang / clang++ / swiftc ─► ld64.lld (xtool SDK)
                         │            (平行、增量式)
                         ├─► plist (libplist): Info.plist, entitlements
                         ├─► resources: xcstrings, ibtool (storyboard/xib ─► nib),
                         │              idl-actool (xcassets ─► Assets.car)
                         ├─► ldid (來自 PATH 或 toolchain.ldid)
                         ├─► zip writer ─► .ipa
                         └─► verify: zip reader + plist + Mach-O parser
```

## 來源對應表

| 檔案 | 職責 |
| --- | --- |
| `src/main.zig` | CLI：zig-clap 頂層指令，以及每個子指令的解析器 |
| `src/config.zig` | `idlproj.yml` 結構定義、合併 `defaults`、驗證、向上檔案搜尋 |
| `src/ynode.zig` | zig-yaml 解析樹的無損 YAML 檢視（保留純量文字；移除註解） |
| `src/toolchain.zig` | SDK/編譯器/ldid 發現、編譯器與連結器旗標集合、`idl check` |
| `src/resources.zig` | 資源快取、嚴格驗證、輸出碰撞計畫與 storyboard/nib 參考檢查 |
| `src/buildstate.zig` | SHA-256 樹狀指紋、快取記錄/輸出完整性與每目錄 OS 鎖定 |
| `src/builder.zig` | 平行增量編譯、連結、套件組裝、簽章、打包、xtool 執行、清理 |
| `src/hosttest.zig` | `type: test` 目標：SwiftPM 套件（複製來源）+ `swift test`，或主機 clang 編譯與執行 |
| `src/codegen.zig` | `xtool.yml`、`Package.swift`、`compile_commands.json`、防止覆蓋非產生檔案的保護機制 |
| `src/pbxproj.zig` | 確定性 Xcode 專案 + 方案；原子式、符號連結安全的發布 |
| `src/metadata.zig` | YAML 驅動的 Info.plist 與 entitlements，由直接編譯、Xcode 和 xtool 編譯共用 |
| `src/plist.zig` | libplist 包裝函式、Xcode `$(VAR)` 展開、CLI 值解析 |
| `src/xcstrings.zig` | String Catalog 轉為 `.strings` / `.stringsdict` |
| `src/zip.zig` | 確定性 ZIP 寫入器（std.compress.flate）與 CRC 檢查讀取器 |
| `src/macho.zig` | Mach-O 標頭與載入指令檢查 |
| `src/verify.zig` | IPA 驗證，供 `build` 與 `verify` 使用 |
| `src/ibtool.zig` | `.xib` / `.storyboard` 轉為 nib 物件圖（davidquesada/ibtool 的移植版） |
| `src/nib.zig` | NIBArchive 物件模型、編碼器與解碼器（`idl ibtool --dump`） |
| `src/xmldom.zig` | 基於 zig-xml 串流讀取器的輕量 DOM |
| `tools/idl-actool` | AssetKit 的 Swift 包裝函式；獨立可執行檔，由 `zig build actool` 建置 |
| `src/jimpactor.zig` | Jimpactor 本機 IPC 協定 v1 的客戶端（`devices`、`install`） |
| `src/scaffold.zig` | `idl init`（來源由 `build.zig` 從 `examples/` 嵌入） |
| `src/fsutil.zig` | 與 Xcode 共用的發現規則、路徑驗證、符號連結檢查 |
| `src/diag.zig` | 單一使用者可見的錯誤訊息通道 |
| `src/sys.zig` | 程序層級的 `std.Io` 與環境（在 `main` 中設定一次）、檔案/程序輔助函式 |

## 相依套件

所有相依套件皆已固定版本於 `build.zig.zon`：

- **zig-clap**：參數解析與說明文字。
- **zig-yaml**：YAML 詞法分析器與解析器，固定版本為上游 `main`（0.3.0；上游無 0.17 版）的 Zig 0.17 移植版。`idl` 直接遍歷其 `Tree`，而非使用 `Yaml.parse`，因為型別化解析器會將 `16.10` 強制轉換為浮點數並遺漏引號。
- **libplist**（libimobiledevice）：讀取與寫入 XML、二進位、JSON 和 OpenStep plists。它以 `git+https://…#2.8.1` 取得（固定版本至特定提交），並由 `build.zig` 中的 `buildLibplist` 從 C 原始碼編譯，而非使用其 autotools 建構。僅建構 C 核心，不包含 libplist++。
- **zig-xml**（ianprime0509）：Interface Builder 文件的 XML 讀取器。固定版本為 0.2.2（Zig 0.16/0.17）。
- **AssetKit**（xtool-org）：將 `.xcassets` 轉換為 `Assets.car`，僅由 `tools/idl-actool` 使用（Swift 套件，固定版本為 1.0.0）。它未連結至 `idl`。
- **Zig std**：deflate、CRC-32、SHA-1、JSON、處理程序與 `translate-c`（`plist.h` 由 `build.zig` 轉換；Zig 0.16+ 無 `@cImport`）。`idl` 僅向 Jimpactor 發出網路請求，目標為 127.0.0.1。

## 設計注意事項

- **確定性程式碼產生。** Xcode 物件 ID 為
  `SHA1("pbxprojgen:<section>:<key>")[0..12]`，因此相同的輸入總是會產生
 相同的 `project.pbxproj`。低層級 ID 保留與早期 Python 產生器的相容性；設定檔特定的設定有意地擴充輸出內容。
- **安全發布。** 新的 `.xcodeproj` 寫入私有相鄰目錄，並透過目錄 FD 相對、不跟隨符號連結的操作（`fstatat(AT_SYMLINK_NOFOLLOW)`、`openat(O_NOFOLLOW)`、
  `renameat`）移至正確位置。因此，最後時刻交換的符號連結不會重定向寫入動作。單元測試涵蓋此部分。
- **永不覆蓋手寫檔案。** 產生的原始碼樹狀結構檔案帶有標記，沒有該標記的檔案會保持不變。
- **編譯前預檢。** 所有選定的工具會在任何資源編譯器執行之前進行探測；所有資源計畫會在應用程式編譯開始之前準備完畢。嚴格模式會拒絕不支援或遺漏的輸入。
- **增量建構。** 每個物件都有 `.cmd` 命令/工具指紋，且 clang 的 `-MMD` 相依檔案列出標頭檔。資源使用 SHA-256 內容尋址快取項目，並在命中時驗證其輸出樹狀結構。僅在輸入指紋以及有效載荷與 IPA 完整性相符時，跳過捆綁/簽署/ZIP。
- **鎖定機制。** 建構/檢查/產生/清除會在 `.idl/build.lock` 中持有作業系統建議性鎖定。清除期間不會解除連結鎖定檔案；關閉描述元即可釋放鎖定。建構會在修改輸出內容之前取得所有選定的鎖定。
- **設定檔產生。** YAML 將深層合併映射至已解析的 debug/release 目標。每個設定檔的中繼資料寫入 `.idl/<profile>/` 下；Xcode 接收兩個設定檔，而 xtool 的清單描述所選的設定檔。
- **可重現的 IPA。** 項目已排序，時間戳記固定，且保留 Unix 模式。僅在使項目變小時才使用 Deflate。
- **範圍環境。** swiftly 的二進位目錄附加至 `PATH` 末尾，而非前置，且僅傳遞給子處理程序的環境中。主機工具保持優先順序。
