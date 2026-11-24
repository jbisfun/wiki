# calculator-ios

[Fossify Calculator](https://github.com/FossifyOrg/Calculator) 以 SwiftUI 在 iOS 上重新打造。

    idl build -c release     # -> build/release/FossifyCalculator.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyCalculator

已移植：計算機引擎（CalculatorImpl，以 Foundation 的 `Decimal` 取代 BigDecimal／EvalEx）及其直向與橫向按鍵配置、長按 C 重設、長按減號變更正負號、長按算式／結果複製；歷史記錄（最近 20 筆，點一下重複使用，長按複製，可清除）；全部九種單位換算器及其所有上游單位，並記住上次使用的單位組合；色彩、按鈕震動回饋與防止手機進入休眠；主畫面計算機小工具（4x4，可調整為 3x3，附 AC，點一下顯示區開啟應用程式）及其設定畫面（背景色彩＋透明度、文字色彩）。

因 iOS 而不得不有的差異：小工具僅能在 launcher-ios 內使用（iOS 主畫面小工具需要 WidgetKit 擴充功能）、沒有應用程式內語言切換，且換算器圖示使用 SF Symbols。

GPL-3.0，與原版相同。
