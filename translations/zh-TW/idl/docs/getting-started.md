# 快速入門

## 需求

| 工具 | 用途 | 安裝方式 |
| --- | --- | --- |
| Zig 0.17.1 | 編譯 `idl` | 發行版套件或 ziglang.org |
| Swift toolchain (clang, clang++, swiftc) | 編譯為 `arm64-apple-ios` | [swiftly](https://www.swift.org/install/linux/) |
| xtool + Darwin SDK | iPhoneOS SDK、`ld64.lld`、compiler-rt、Swift 資源 | [xtool](https://github.com/xtool-org/xtool)，接著執行 `xtool setup` |
| ldid | 臨時簽署 (ad-hoc signing) | [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid) 的發布二進位檔或發行版套件 |

`idl` 不會安裝任何東西。它會尋找這些工具，而 `idl check`（以及
每次建置）會在發現遺漏項目時停止並顯示錯誤訊息。你不需要
Python、Make、`zip`、`unzip` 或 `llvm-objdump`：`idl` 會自行寫入 ZIP、解析
Mach-O 檔案並處理 plists（使用 libplist）。

## 建置 idl

    zig build                         # 在 ./zig-out/bin/idl 中的除錯版本
    zig build -Doptimize=ReleaseSafe  # 最佳化版本
    zig build test                    # 單元測試

`zig build` 會下載其相依套件，這些套件已固定在 `build.zig.zon` 中：

- [zig-clap](https://github.com/Hejsil/zig-clap) 0.12.0：命令列解析
- [zig-yaml](https://github.com/kubkon/zig-yaml) 0.3.0：`idlproj.yml` 解析
  （上游尚未有 Zig 0.17 版本；固定在
  [siketyan/zig-yaml](https://github.com/siketyan/zig-yaml) `zig-0.17.0` 的上游 `main` 移植版）
- [zig-xml](https://github.com/ianprime0509/zig-xml) 0.2.2：Interface Builder 文件
- [libplist](https://github.com/libimobiledevice/libplist) 2.8.1：屬性
  清單。它會從 git 取得，並由 `build.zig` 從 C 原始碼編譯。

要在任何地方使用 `idl`，請將 `zig-out/bin/idl` 複製到 `PATH` 中的目錄，
或使用 `zig build -p ~/.local`。

`idl init` 只會建立應用程式原始碼、`.gitignore` 和 `idlproj.yml`。Info.plist
和權限清單會從 YAML 產生；在
`info:` 和 `entitlements:` 下設定任意鍵值。不需要來源 XML。

對於資產目錄 (asset catalogs)，也請使用 PATH 上的 Swift toolchain 執行 `zig build actool`。此輔助工具預設使用共享的 Swift 執行階段程式庫；當獨立於該 toolchain 分發時，請使用
`-Dactool-static=true`。

## 檢查 toolchain

    idl check

範例輸出：

    sdk              ~/.swiftpm/.../iPhoneOS27.2.sdk
    sdk version      27.2
    swift resources  ~/.swiftpm/.../usr/lib/swift
    ld64.lld         ~/.swiftpm/.../toolset/bin/orig/ld64.lld
    compiler-rt      ~/.swiftpm/.../libclang_rt.ios.a
    clang            ~/.local/share/swiftly/bin/clang
    ...

如果項目顯示 `missing`，請安裝該工具，或在 `idlproj.yml` 的
`toolchain:` 下設定其位置。僅當目標為 `builder: xtool` 時才需要 xtool。

## 建置範例

    idl build                 # 所有目標
    idl build ObjCExample     # 單一目標
    idl -v build              # 列印每個編譯器/連結器命令

輸出：

    examples/objc-app/build/ObjCExample.ipa
    examples/swift-app/build/SwiftExample.ipa
    examples/xtool-swiftpm/xtool/XtoolExample.ipa

每次建置後，`idl verify` 會檢查 IPA：ZIP CRC、Info.plist 鍵值、可執行檔的權限模式、輕量的 arm64 `MH_EXECUTE` 二進位檔案、`LC_MAIN`、`LC_BUILD_VERSION` 中的 iOS
平台、`LC_CODE_SIGNATURE`（除非目標未簽署），以及確認它僅相依於系統或內建的 dylibs。

## 開始你自己的應用程式

    idl init MyApp --lang objc --bundle-id com.example.myapp
    cd MyApp
    idl build
    idl gen         # MyApp.xcodeproj + compile_commands.json

`idl` 會搜尋目前目錄及其父目錄中的 `idlproj.yml`。傳入
`-f path/to/idlproj.yml` 以使用不同的檔案。
