# 在 Linux 上開發 iOS

`idl` 是一個小型 Zig 工具，可在 Linux 上建置 Objective-C、Swift、C 與 C++ 的 iOS 應用程式。
只要一個檔案 `idlproj.yml`，就能設定工具鏈與每一個應用程式。
`idl` 會根據該檔案：

- 產生程式碼：具確定性的 `.xcodeproj` 專案（含共用 scheme）、供 xtool 使用的
  `xtool.yml` 與 `Package.swift`，以及供 clangd / sourcekit-lsp 使用的 `compile_commands.json`
- 執行建置：呼叫 clang、swiftc、xtool 的 `ld64.lld` 與 `ldid`，
  處理 Info.plist、編譯 storyboard、XIB 與資源目錄（asset catalog）、複製
  資源、進行 ad-hoc 簽署、寫出 IPA，並檢查結果

建置步驟來自 LiveContainer 所使用的 Linux 建置方式。

## 快速開始

    xtool setup                   # Darwin SDK -> ~/.swiftpm/swift-sdks/darwin.artifactbundle
    zig build                     # builds ./zig-out/bin/idl (Zig 0.14.1)
    ./zig-out/bin/idl check       # verify the toolchain
    zig build actool              # optional: .xcassets compiler (needs swift)
    ./zig-out/bin/idl build --strict -c release  # preflight, then build every example

透過 [Jimpactor](https://github.com/jpdagostin0/jimpactor) 安裝到手機上。
Jimpactor 是一個側載（sideloading）系統匣應用程式，會使用你的 Apple 帳號為 IPA 簽署（其他
選項請見 [workflows](docs/workflows.md#install-on-a-device-through-jimpactor)）：

    idl devices list
    idl install "My iPhone" MyApp

建立新的應用程式：

    idl init MyApp --lang swift --bundle-id com.example.myapp
    cd MyApp && idl build

## 建置自動化

    idl check --strict -c release
    idl build --strict -c debug MyApp
    idl build --strict -c release MyApp

YAML 的 `configurations:` 可覆寫旗標、套件組合識別、中繼資料與權限（entitlements）。
Debug／release 產出物彼此隔離。直接建置會快取資源編譯、
打包、簽署與封裝；同時進行的 build／gen／clean 操作會被鎖定。
請見 [workflows](docs/workflows.md#strict-preflight-and-build-profiles)。

## 程式碼品質

    idl fmt [--check]      # clang-format (C/ObjC/C++/ObjC++) + swift-format, configs generated from YAML
    idl lint [--analyze]   # clang -Wall, swiftc -typecheck, clang-tidy, analyzer, all with the real build flags
    idl test               # bundle checks (arm64/iOS/signed, @rpath resolution, plists) + `tests:` commands

idl 只負責協調已安裝的工具，並將它們的診斷訊息合併成一份
報告。請見 [configuration](docs/configuration.md#formatting-linting-and-tests-idl-fmt-idl-lint-idl-test)。

## 目錄配置

    idlproj.yml        configuration for the examples in this repository
    build.zig(.zon)    Zig build; pulls zig-clap, zig-yaml, zig-xml and libplist
    src/               the idl tool (see docs/architecture.md)
    tools/idl-actool/  Swift wrapper around AssetKit for .xcassets
    examples/          ObjC, Swift, storyboard/XIB/asset-catalog and xtool/SwiftPM
                       apps, plus xcconfig patterns
    docs/              documentation

## 文件

- [開始使用](docs/getting-started.md)
- [idlproj.yml 參考](docs/configuration.md)
- [常見工作流程](docs/workflows.md)
- [已知限制](docs/limitations.md)
- [架構](docs/architecture.md)

## 測試

    zig build test       # unit tests (config, plist, pbxproj, zip, Mach-O, nib, ibtool, ...)
    zig build check      # idl check
    zig build examples   # idl build --gen for every example (real arm64 builds)

Ad-hoc `ldid` 簽章並不等同於佈建（provisioning）。安裝 IPA 之前，請先使用你慣用的
簽署或側載工具重新簽署。
