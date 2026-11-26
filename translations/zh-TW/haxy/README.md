<p align="center">
<code>                                             
░██    ░██     ░████    ░██    ░██ ░██    ░██
░██    ░██    ░██ ░██    ░██  ░██   ░██  ░██ 
░██    ░██   ░██   ░██    ░█████     ░█████  
░█████████  ░█████████     ░███       ░███   
░██    ░██ ░██      ░██    ░████      ░██    
░██    ░██ ░██      ░██   ░██ ░██     ░██    
░██    ░██ ░██      ░██  ░██   ░██    ░██    
                                             </code></p>

**Haxy 現已進入預覽階段！立即體驗：https://try.haxy.net/**

您正在檢視 Haxy，這是一個以本機為優先且基於文字的 Git 託管平台。Haxy 提供文字使用者介面（TUI），您可以在終端機或網頁上檢視。掌握資料的本機控制權，搭上 TUI 列車！

以下是它在終端機與網頁上的樣貌：

<p align="center">
<a href="https://raw.githubusercontent.com/xit-vcs/haxy/refs/heads/master/docs/screenshots/terminal.avif"><img src="docs/screenshots/terminal.avif" width="49%" /></a>
<a href="https://raw.githubusercontent.com/xit-vcs/haxy/refs/heads/master/docs/screenshots/web.avif"><img src="docs/screenshots/web.avif" width="49%" /></a>
</p>

## 為什麼需要另一個 Git 託管平台？

Haxy 基於兩個設計理念：

### 1. 將專案中繼資料（議題、修補程式與討論）儲存在儲存庫中

將專案中繼資料保留在儲存庫中有幾個好處：

* 您可以輕鬆地將其複製到不同的 Haxy 執行個體。
* 您可以在本機檢視/編輯，然後稍後推送變更，就像處理程式碼一樣。

您仍然可以透過 Haxy 執行個體的 UI 來編輯這些資料，就像使用其他任何 Git 託管平台一樣。此外，您也可以在本機執行 Haxy 二進位檔案，以離線方式瀏覽儲存庫的議題和其他中繼資料。如果您擁有儲存庫的推送權限，您可以在本機進行變更，然後稍後推送。

Haxy 儲存庫有一個特殊的分支 `haxy/events`，用於存放事件。每次建立或更新專案中繼資料時，都會產生一個事件。每個提交對應一個事件，該事件以 JSON 格式儲存在提交訊息本身中。伺服器在收到這些事件時會將其消耗到資料庫中——本質上是一種事件溯源（event sourcing）的形式。

[閱讀更多](docs/event.md) 關於事件系統。

### 2. 提供透過 SSH 服務的 TUI，以及網頁 UI

Haxy 提供透過 SSH 服務的文字使用者介面（TUI），因此您可以完全從終端機瀏覽 Haxy 執行個體。這些有時被稱為 SSH 應用程式。它們的一大優勢是，您會自動使用 SSH 金鑰進行驗證，因此在 Haxy 執行個體上建立帳戶並將其與您的 SSH 公開金鑰關聯可以立即完成。

此外，Haxy 提供網頁 UI，以提供更典型的網頁瀏覽器體驗。網頁 UI 只是在您的瀏覽器中呈現 TUI。這聽起來令人恐懼，但網頁渲染器仍使用標準的 HTML 控制項。渲染器由小型 WebAssembly 二進位檔案執行，但頁面也會先由伺服器渲染，因此即使停用腳本，也能檢視內容。

[閱讀更多](docs/tui.md) 關於 TUI。

## 如何啟動這個小工具並完成任務

要建置，請安裝 zig 0.17.0 並執行 `zig build`，你會在 `zig-out/bin/haxy` 找到二進位檔案。

在生產伺服器上，你可以使用 `serve` 子命令來執行此二進位檔案。[閱讀更多](docs/host.md) 關於自我主機的資訊。

要在本機模式運行，只需在任何 git 儲存庫中執行它而無需指定子命令。它會為該儲存庫顯示一個完全離線的 haxy UI。[閱讀更多](docs/local.md) 關於本機模式的資訊。

嘗試 Haxy 最簡單的方式如下：

```
zig build try
```

這將啟動一個伺服器，使用存放在 `temp-try` 目錄中的假資料。接著它會直接在終端機中啟動 TUI（你可以按 Escape 鍵退出）。此外，你可以在 http://localhost:8080 查看 Web UI。

一個有趣的測試是將 Haxy 本身推送到伺服器。你可以透過執行以下命令來完成此操作，該命令將使用 SSH 將其推送到伺服器：

```
GIT_SSH_COMMAND='ssh -p 8022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -i temp-try/key' git push localhost:admin:haxy HEAD:master
```

之後，前往 UI 中的 admin 使用者，你將會看到 Haxy 的儲存庫頁面：http://localhost:8080/admin:haxy/files/branch:master

*"來吧，Alex！你一直夢想著展開一場大冒險！讓這成為我們的初次旅程吧！" -- Lunar: Silver Star Story*
