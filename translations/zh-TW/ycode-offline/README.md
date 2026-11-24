# ycode-offline

ycode 的 Lua 外掛，用來關閉帳號與線上功能：

- 啟動時不自動登入（`%hookf client::authenticate` 從不呼叫 `%orig`）
- 吞掉 `client::*`、`collab::*`、`collab_panel::*`、`channel_modal::*`、
  `onboarding::SignIn`/`OpenAccount`、`zed::OpenAccountSettings`、`auto_update::Check`
- 隱藏登入按鈕、使用者選單／頭像、協作面板按鈕與引導橫幅
- 關閉遙測、關閉自動更新、編輯預測提供者設為 `none`
- 透過 `ycode.kv_set` 關閉升級推銷／廣告橫幅（「Welcome to Zed AI — Sign In to Try GPT Luna」、試用
  結束、編輯預測推銷、更新公告），並封鎖
  編輯預測引導對話框
- 從命令面板中隱藏帳號／協作命名空間（`ycode.palette_hide`）

設定會寫入 ycode 記憶體內的外掛層（`ycode.settings{}`），位於 settings.json 之上，
且絕不會寫入磁碟。

## 安裝

    # from the ycode-offline clone
    ln -s "$PWD" ~/.config/zed/hooks/ycode-offline

然後執行「ycode: reload hooks」。若要復原，移除連結並重新載入（橫幅的關閉狀態
會像點擊「dismiss」一樣被儲存，並會保留）。啟動登入的否決
要到下次啟動才會生效。
