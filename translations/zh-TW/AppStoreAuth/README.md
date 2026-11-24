# AppStoreAuth

適用於 iOS 的裝置端 App Store 登入，從 LiveContainer 中拆分出來。

| 產品 | 功能 |
| --- | --- |
| `NativeStore` | 連接 StoreServices / AMD 的 Objective-C 橋接層 |
| `SAPKit` | 在模擬機器中執行 Apple 的 SAP 簽署器（透過 MacADICore 使用 Unicorn） |
| `MacAnisetteKit` | Mac CoreADI anisette（MID/OTP）、機器佈建 |
| `AppStoreCore` | App Store 驗證流程與用戶端 |

```swift
.package(url: "https://github.com/jbisfun/AppStoreAuth", branch: "main")
```

相依於 [MacADICore](https://github.com/jbisfun/MacADICore)。衍生自
AnisetteKit（AGPL-3.0，請參閱 LICENSE）；SAPKit 在
`Sources/SAPKit` 中附有自己的 MIT 聲明。
