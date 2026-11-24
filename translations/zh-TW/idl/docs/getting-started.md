# 開始使用

## 需求

| 工具 | 用途 | 安裝 |
| --- | --- | --- |
| Zig 0.14.1 | 建置 `idl` | 發行版套件或 ziglang.org |
| Swift toolchain (clang, clang++, swiftc) | 為 `arm64-apple-ios` 編譯 | [swiftly](https://www.swift.org/install/linux/) |
| xtool + Darwin SDK | iPhoneOS SDK、`ld64.lld`、compiler-rt、Swift 資源 | [xtool](https://github.com/xtool-org/xtool)，然後執行 `xtool setup` |
| ldid | ad-hoc 簽署 | [ProcursusTeam/ldid](https://github.com/ProcursusTeam/ldid) 發行版執行檔或發行版套件 |

`idl` 絕不會安裝任何東西。它只會尋找這些工具，而 `idl check`（以及
每次建置）會在缺少任何工具時中止，並顯示指出缺少項目的錯誤。你不需要
Python、Make、`zip`、`unzip` 或 `llvm-objdump`：`idl` 會自行寫入 ZIP、解析
Mach-O 檔案，並處理 plist（透過 libplist）。

## 建置 idl

    zig build                         # Debug build in ./zig-out/bin/idl
    zig build -Doptimize=ReleaseSafe  # optimized build
    zig build test                    # unit tests

`zig build` 會下載其相依套件，這些套件已在 `build.zig.zon` 中固定版本：

- [zig-clap](https://github.com/Hejsil/zig-clap) 0.10.0：命令列解析
- [zig-yaml](https://github.com/kubkon/zig-yaml) 0.1.1：`idlproj.yml` 解析
- [libplist](https://github.com/libimobiledevice/libplist) 2.8.1：屬性
  清單（property list）。它從 git 取得，並由 `build.zig` 以 C 原始碼編譯。

若要在任何地方使用 `idl`，請將 `zig-out/bin/idl` 複製到 `PATH` 中的資料夾，
或使用 `zig build -p ~/.local`。

`idl init` 只會建立應用程式原始碼、`.gitignore` 與 `idlproj.yml`。Info.plist
與 entitlements 由 YAML 產生；請在
`info:` 與 `entitlements:` 下設定任意鍵值。不需要任何 XML 原始檔。

若需要資源目錄（asset catalog），請在 PATH 中有 Swift 工具鏈的情況下，另外執行 `zig build actool`。這個輔助工具預設使用共用的 Swift 執行階段函式庫；若要脫離該工具鏈獨立散布，請使用
`-Dactool-static=true`。

## 檢查工具鏈

    idl check

範例輸出：

    sdk              ~/.swiftpm/.../iPhoneOS27.2.sdk
    sdk version      27.2
    swift resources  ~/.swiftpm/.../usr/lib/swift
    ld64.lld         ~/.swiftpm/.../toolset/bin/orig/ld64.lld
    compiler-rt      ~/.swiftpm/.../libclang_rt.ios.a
    clang            ~/.local/share/swiftly/bin/clang
    ...

如果某個項目顯示 `missing`，請安裝該工具，或在 `idlproj.yml` 的
`toolchain:` 下設定其位置。只有 `builder: xtool`
目標才需要 xtool。

## 建置範例

    idl build                 # all targets
    idl build ObjCExample     # one target
    idl -v build              # print every compiler/linker command

輸出：

    examples/objc-app/build/ObjCExample.ipa
    examples/swift-app/build/SwiftExample.ipa
    examples/xtool-swiftpm/xtool/XtoolExample.ipa

每次建置之後，`idl verify` 會檢查 IPA：ZIP 的 CRC、Info.plist 的鍵、
執行檔的模式、精簡的 arm64 `MH_EXECUTE` 二進位檔、`LC_MAIN`、`LC_BUILD_VERSION` 中的 iOS
平台、`LC_CODE_SIGNATURE`（除非目標為
未簽署），以及它只相依於系統或隨附的 dylib。

## 建立你自己的應用程式

    idl init MyApp --lang objc --bundle-id com.example.myapp
    cd MyApp
    idl build
    idl gen         # MyApp.xcodeproj + compile_commands.json

`idl` 會在目前資料夾及其上層資料夾中搜尋 `idlproj.yml`。傳入
`-f path/to/idlproj.yml` 即可使用其他檔案。
