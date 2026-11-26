# 在 Linux 上進行 iOS 開發

`idl` 是一個小型的 Zig 工具，可在 Linux 上建構 Objective-C、Swift、C 和 C++ iOS 應用程式。單一檔案 `idlproj.yml` 即可設定工具鏈與所有應用程式。根據該檔案，`idl`：

- 產生程式碼：具有共用方案的確定性 `.xcodeproj` 專案、用於 xtool 的 `xtool.yml` + `Package.swift`，以及用於 clangd / sourcekit-lsp 的 `compile_commands.json`
- 執行建構：它會呼叫 clang、swiftc、xtool 的 `ld64.lld` 和 `ldid`，處理 Info.plist、編譯 storyboards、XIBs 和 asset catalogs、複製資源、進行 ad-hoc 簽章、寫入 IPA，並檢查結果

這些建構步驟來自 LiveContainer 所使用的 Linux 建構。

## 快速開始

    xtool setup                   # Darwin SDK -> ~/.swiftpm/swift-sdks/darwin.artifactbundle
    zig build                     # 建構 ./zig-out/bin/idl (Zig 0.17.1)
    ./zig-out/bin/idl check       # 驗證工具鏈
    zig build actool              # 選配：.xcassets 編譯器 (需要 swift)
    ./zig-out/bin/idl build --strict -c release  # 預檢，然後建構每個範例

透過 [Jimpactor](https://github.com/jpdagostin0/jimpactor) 安裝至手機，
這是一個側載托盤應用程式，會使用您的 Apple 帳戶對 IPA 進行簽章（其他選項請見 [workflows](docs/workflows.md#install-on-a-device-through-jimpactor)）：

    idl devices list
    idl install "My iPhone" MyApp

開始新的應用程式：

    idl init MyApp --lang swift --bundle-id com.example.myapp
    cd MyApp && idl build

## 建構自動化

    idl check --strict -c release
    idl build --strict -c debug MyApp
    idl build --strict -c release MyApp

YAML `configurations:` 會覆寫旗標、bundle 識別碼、中繼資料和權限。
Debug/release 的產物是隔離的。直接建構會快取資源編譯、捆綁、簽章和封裝；並行的建構/產生/清理操作已鎖定。
請參閱 [workflows](docs/workflows.md#strict-preflight-and-build-profiles)。

## 程式碼品質

    idl fmt [--check]      # clang-format (C/ObjC/C++/ObjC++) + swift-format，設定從 YAML 產生
    idl lint [--analyze]   # clang -Wall, swiftc -typecheck, clang-tidy, analyzer，皆使用實際的建構旗標
    idl test               # bundle 檢查 (arm64/iOS/已簽章、@rpath 解析、plists) + `tests:` 命令，
                           # 以及 `type: test` 目標：XCTest/swift-testing (SwiftPM) 或 C 測試在 Linux 主機上執行

idl 僅協調已安裝的工具，並將它們的診斷資訊合併為單一報告。請參閱 [configuration](docs/configuration.md#formatting-linting-and-tests-idl-fmt-idl-lint-idl-test)。

## 目錄結構

    idlproj.yml        此儲存庫中範例的設定
    build.zig(.zon)    Zig 建構；拉取 zig-clap、zig-yaml、zig-xml 和 libplist
    src/               idl 工具 (請見 docs/architecture.md)
    tools/idl-actool/  AssetKit 的 Swift 包裝函式，用於 .xcassets
    examples/          ObjC、Swift、storyboard/XIB/asset-catalog 和 xtool/SwiftPM
                       應用程式、主機單元測試 (swift-tests、c-tests)，以及 xcconfig 樣式
    docs/              文件

## 文件

- [Getting started](docs/getting-started.md)
- [idlproj.yml reference](docs/configuration.md)
- [Common workflows](docs/workflows.md)
- [Known limitations](docs/limitations.md)
- [Architecture](docs/architecture.md)

## 測試

    zig build test       # 單元測試 (設定、plist、pbxproj、zip、Mach-O、nib、ibtool、...)
    zig build check      # idl check
    zig build examples   # idl build --gen 用於每個範例 (實際的 arm64 建構)

ad-hoc `ldid` 簽章並非 provisioning。安裝前，請使用您常用的簽章或側載工具重新簽章 IPA。
