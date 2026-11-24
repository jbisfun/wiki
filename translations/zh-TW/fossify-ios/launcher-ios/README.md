# launcher-ios

將 Fossify iOS 移植版整合為單一應用程式（「Fossify」），並以 [Fossify Launcher](https://github.com/FossifyOrg/Launcher) 的移植版作為其主畫面：內含的應用程式扮演已安裝的應用程式。開啟的應用程式在各自的視窗中執行，下方有 AOSP 導覽列與通知欄（SystemUI 移植）。分享給啟動器的 vCard 會在 Contacts 的匯入對話框中開啟。

    idl build -c release     # -> build/release/FossifyLauncher.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyLauncher

已移植：分頁式主畫面格線（列數／欄數依設定，滑動或快速撥動切換頁面，頁面指示器）與擴充座列；長按項目開啟其選單（應用程式資訊 = 該應用程式的「關於」、重新命名、移除；在應用程式抽屜中隱藏圖示；小工具則可調整大小／重新設定／移除），持續移動即可拖曳：跨頁（停在側邊，最後會多出一頁）、移入擴充座、移到另一個圖示上以建立資料夾；資料夾（開啟、重新命名、重新排序、拖出、移除，最多 16 個應用程式）；應用程式抽屜（上滑／快速撥動開啟，在頂端下拉關閉，搜尋時按「前往」會啟動第一個符合項目，格線附快速捲動列，長按可拖曳到主畫面）；小工具清單（在空白主畫面長按 > 小工具：依應用程式列出各自的小工具，可搜尋；拖曳到格線上，放置時會執行其設定畫面，取消則移除；調整大小的框線與上游相同）；隱藏圖示畫面；重新命名對話框；設定（自訂色彩、管理隱藏圖示、抽屜欄數／搜尋列／自動顯示鍵盤／開啟應用程式時關閉抽屜／標籤、主畫面列數／欄數／標籤、桌布、系統導覽、快速設定圖磚、關於）；在主畫面向下快速撥動會開啟通知欄（expandNotificationsPanel）；首次執行時與上游一樣填入擴充座（撥號、簡訊、瀏覽器、商店、相機 -> Phone、Messages、Contacts、Gallery、Camera）。版面配置與隱藏圖示以 JSON 存放於 Application Support/Launcher，設定則是以 `launcher_` 為前綴的 UserDefaults。

因 iOS 而不得不有的差異：啟動器無法成為系統主畫面、無法列出或解除安裝其他應用程式、無法讀取或設定系統桌布、無法鎖定螢幕或釘選捷徑，因此：沒有解除安裝／設為預設／點兩下鎖定／應用程式捷徑；小工具是內含應用程式的 SwiftUI 小工具（`Model/WidgetRegistry.swift`），而非其他應用程式的；背景由使用者從 `Resources/Wallpapers.bundle` 中的 AOSP 桌布（Apache-2.0，見其 NOTICE；預設為「Android 14」）、「照片」中的影像或佈景主題背景中挑選（此時標籤改用佈景主題的文字色彩而非白色）；Home 會像上游的主畫面按鈕一樣關閉抽屜。

SystemUI 移植（`Sources/System`）：AOSP 三按鈕導覽列（ic_sysbar_back/home/recent、48dp 列、70dp 按鍵，內容上方有淺色／深色圖示；應用程式與其全高工作表會因此內縮）或手勢導覽（把手：上滑 = 主畫面、上滑並按住 = 總覽、從任一邊緣向內滑 = 返回），可在設定 > 系統導覽中選擇。返回會依序：收起鍵盤、取消最上層的警示、關閉最上層的工作表、彈出最上層的導覽堆疊、執行應用程式的 `onBackPressed` 回呼（commons 的 `BackNavigation.swift`；Paint 與 Notes 會在此詢問是否放棄未儲存的變更），否則將應用程式送到背景；在主畫面時則清除抽屜搜尋、關閉抽屜、調整大小的框線與資料夾。Home 會關閉所有項目並回到主畫面。總覽：最多 8 個最近使用應用程式的卡片，附其最後的快照，可左右滑動、將卡片上滑以關閉、點一下切換，以及「全部清除」；最近使用的應用程式仍保持存活（其視窗只是被隱藏）。從任何位置的頂端邊緣拉出通知欄：標頭（時鐘、日期、電池）＋ 2x2 快速圖磚，再拉一次則顯示分頁式 2x4 圖磚、亮度滑桿與頁尾（編輯、設定）；圖磚：手電筒、深色主題、自動旋轉、保持螢幕開啟、錄音（Voice Recorder）、鬧鐘／計時器（Clock）、相機、計算機，並提供 AOSP 風格的圖磚編輯（拖曳重新排序、點一下新增／移除、重設）、載入曲目時顯示 Music Player 媒體控制，以及依應用程式分組的本行程已送達通知（滑動關閉、點一下開啟該應用程式、全部清除）。啟動器設定已向 commons 的 `SystemSettingsRegistry` 註冊（桌布、主畫面、導覽模式、快速設定圖磚、隱藏的應用程式、Fossify Keyboard 設定、內含應用程式清單），供 Settings 應用程式使用。

因 iOS 而不得不有的 SystemUI 差異：它只涵蓋本應用程式，因此 iOS 自己的狀態列、主畫面指示條手勢（延後處理，再滑一次仍會離開）、控制中心與鍵盤仍會顯示在它上方；沒有 Wi-Fi／藍牙／飛航模式／勿擾模式／定位／投放圖磚（應用程式無法切換這些功能）；只列出本應用程式的通知，且點一下會開啟所屬的應用程式，而不是執行其通知處理常式；導覽列在橫向時仍位於底部，並位於鍵盤下方（沒有輸入法返回鍵）；Camera 在最近使用項目中只保留其快照（其擷取工作階段無法在隱藏時執行），重新開啟時會重新啟動。

內含：Calculator、Calendar、Camera、Clock、Contacts、Documents、File Manager、Gallery、Keyboard（亦可作為系統鍵盤：設定 > 一般 > 鍵盤 > 鍵盤 > 加入新鍵盤 > Fossify Keyboard；其設定／剪貼簿按鈕會在啟動器中開啟 `fossify-keyboard://`）、Messages、Music Player、Notes、Paint、Phone、Thank You、Voice Recorder。分享給啟動器的檔案會依類型（`BundledApp.handling`）分流：vCard 到 Contacts、.ics 到 Calendar、文字到 Notes、文件到 Documents、音訊到 Music Player、影像到 Paint，其餘到 File Manager。通知會經由 commons 的 `NotificationHub`，因此 Clock 與 Calendar 不會互相取代對方的委派。

每個應用程式仍可單獨建置。其儲存庫分為靜態的 `<App>Kit` 模組（`Sources/`，公開的進入檢視 `CalculatorRoot` / `ContactsRoot`）與單一檔案的應用程式目標（`App/main.swift`）。啟動器從 `fossify-ios/` 中並列簽出的目錄（calculator-ios、contacts-ios、commons-ios）連結這些 Kit 與 [commons-ios](https://github.com/jbisfun/commons-ios)。被託管的應用程式不再取得 `\.closeApp`（因此沒有 `CloseAppButton`）；它們改為取得 `\.backPressedDispatcher` 與 `\.finishApp`。啟動器原始碼：`Sources/Model`（BundledApp、設定、版面配置儲存區、小工具登錄表、桌布）、`Sources/UI`（主畫面、抽屜、小工具清單、選單、設定）、`Sources/System`（工作視窗、導覽列、最近使用項目、通知欄、快速設定、系統設定註冊）、`Sources/main.swift`。

新增應用程式：為它加上 Kit/App 分離結構，將其 Kit 目標加入 `idlproj.yml`，把它的 Info.plist 鍵合併到啟動器的 `info:` 中，在 `BundledApp`（`Model/BundledApp.swift`，並把它的檔案類型加入 `handling`）與 `AppView`（`UI/LauncherView.swift`；之後它也會出現在 `SystemSettingsRegistry.apps` 中）新增一個 case，並提供其 180 px 圖示 `Resources/AppIcons/<name>.png`；其小工具（`<App>Widgets.all`）則放入 `widgetProviders`。Kit 的資源（例如 Calendar 的 `Holidays.bundle`、Camera 的 `CameraSounds.bundle`）必須複製到 `Resources/` 中，因為 idl 資源無法指向目標目錄之外。

GPL-3.0。
