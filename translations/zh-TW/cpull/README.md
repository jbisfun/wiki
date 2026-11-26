# cpull

cpull 是 jbisfun 基於 xit-vcs 專案的 [haxy](https://github.com/xit-vcs/haxy) 所建立的分支，並為 [pull](https://github.com/jbisfun/pull) 工作區（workspace mode、堆疊、主題式網頁介面）重新命名並擴充。以下內容若未特別提及工作區者，皆屬於 haxy 的功能。

您現在看到的是 cpull，一個以本地為優先且基於文字的 git 託管服務。cpull 提供文字使用者介面（TUI），您可以在終端機或網頁上檢視。掌握本地的資料控制權，搭上 TUI 列車吧！

以下是它在終端機與網頁上的外觀：

<p align="center">
<a href="https://raw.githubusercontent.com/xit-vcs/haxy/refs/heads/master/docs/screenshots/terminal.avif"><img src="docs/screenshots/terminal.avif" width="49%" /></a>
<a href="https://raw.githubusercontent.com/xit-vcs/haxy/refs/heads/master/docs/screenshots/web.avif"><img src="docs/screenshots/web.avif" width="49%" /></a>
</p>

## 為何需要另一個 git 託管服務？

cpull 基於兩個設計理念：

### 1. 將專案中繼資料（議題、修補程式和討論）儲存在儲存庫中

將專案中繼資料保留在儲存庫中有幾個好處：

* 您可以輕鬆地將其複製到不同的 cpull 執行個體。
* 您可以在本地檢視/編輯，然後稍後推送變更，就像處理程式碼一樣。

您仍然可以透過 cpull 執行個體的介面來編輯這些資料，就像其他任何 git 託管服務一樣。此外，您也可以在本機執行 cpull 二進位檔案，以離線方式瀏覽儲存庫的議題和其他中繼資料。如果您擁有該儲存庫的推送權限，您可以在本地進行變更並稍後推送。

cpull 儲存庫有一個特殊的分支 `cpull/events`，用於存放事件。每次建立或更新專案中繼資料時，就會產生一個事件。每個提交對應一個事件，並以 JSON 格式儲存在提交訊息本身中。伺服器在收到這些事件時會將其消耗至資料庫中——本質上是一種事件來源（event sourcing）的形式。

[閱讀更多](docs/event.md) 關於事件系統。

### 2. 提供透過 SSH 服務的 TUI，以及網頁介面

cpull 提供透過 SSH 服務的文字使用者介面（TUI），因此您可以完全從終端機瀏覽 cpull 執行個體。這些有時被稱為 SSH 應用程式。它們的一大優勢是會自動使用您的 SSH 金鑰進行驗證，因此在 cpull 執行個體上建立帳戶並將其與您的 SSH 公開金鑰關聯可以立即完成。

此外，cpull 提供網頁介面，以提供更典型的網頁瀏覽器體驗。網頁介面僅將 TUI 呈現於您的瀏覽器中。這聽起來可能令人恐懼，但網頁渲染器仍使用標準的 HTML 控制項。渲染器由小型 webassembly 二進位檔案執行，但頁面也會先在伺服器端進行渲染，因此即使停用腳本也能檢視內容。

[閱讀更多](docs/tui.md) 關於 TUI。

## 如何啟動這個小東西並完成工作

要建置，請安裝 zig 0.17.0 並執行 `zig build`，您會在 `zig-out/bin/cpull` 找到二進位檔案。

在生產伺服器上，您可以使用 `serve` 子命令執行此二進位檔案。[閱讀更多](docs/host.md) 關於自行託管。

要在本地模式運行，只需在任何 git 儲存庫中執行它而無需指定子命令即可。它會顯示僅針對該儲存庫的完全離線 cpull UI。[閱讀更多](docs/local.md) 關於本地模式。

在 [pull](https://github.com/jbisfun/pull) 工作區內運行它，它將涵蓋工作區中的所有儲存庫，以及堆疊：跨儲存庫共同提交的變更。`--web-listen 127.0.0.1:8080` 作為背景作業僅服務該無需帳戶的網頁介面。[閱讀更多](docs/workspace.md) 關於工作區模式。

嘗試 cpull 最簡單的方式如下：

```
zig build try
```

這將啟動一個伺服器，使用儲存在 `temp-try` 目錄中的假資料。然後它會在您的終端機中直接啟動 TUI（您可以按 escape 鍵退出）。此外，您可以在 http://localhost:8080 檢視網頁介面。

一個有趣的測試是將 cpull 本身推送到伺服器。您可以執行以下指令，透過 SSH 將其推送到伺服器：

```
GIT_SSH_COMMAND='ssh -p 8022 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -i temp-try/key' git push localhost:admin:cpull HEAD:master
```

之後，前往 UI 中的 admin 使用者，您就會看到 cpull 的儲存庫頁面：http://localhost:8080/admin:cpull/files/branch:master

「加油，亞歷克斯！你一直夢想著展開一場大冒險！就讓這成為我們的初次旅程吧！」——《露娜：銀星物語》
