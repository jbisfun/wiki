# CI (`src/ci`)

cpull 的工作區伺服器會為其拉取工作區中的 [idl](https://github.com/jbisfun/idl) 專案執行 CI（每個包含 `idlproj.yml` 的目錄，最多向下五層）。它是 idlci 的 Zig 移植版本：相同的作業佇列、Jenkins 風格的頁面、JSON API 和 CLI。

- **伺服器**：`cpull --workspace DIR --web-listen ADDR [--ci-jobs N] [--ci-watch [--ci-watch-interval S]]`。
  頁面位於 `/ci`（儀表板、`/ci/projects/<path>`、`/ci/jobs`、`/ci/jobs/<id>` 帶有即時
  主控台）。`--ci-watch` 會在專案（或目標目錄）的 git HEAD 變動時排入 `build` 和 `test`。
- **API**（idlci 的，位於 `/ci` 下）：`GET /ci/api/health`、`GET /ci/api/projects[/<path>]`、
  `GET|POST /ci/api/jobs`、`GET /ci/api/jobs/<id>`、`POST /ci/api/jobs/<id>/cancel|retry[?by=]`、
  `GET /ci/api/jobs/<id>/log?offset=|tail=`、`GET /ci/api/jobs/<id>/events`（伺服器發送的事件）。
- **CLI**：`cpull ci queue|jobs|log|cancel|retry`（`cpull ci --help`）。
- **MCP**：pull 的 `ci_*` 工具（`pull mcp`）。

狀態存放在 `$ROOT/.pull/cpull/ci/`（`ci.db` 使用 idlci 的結構，`logs/<id>.log`、
`serve.lock`）；伺服器會將其位址寫入 `$ROOT/.pull/cpull/serve.addr`。首次啟動時，
會複製現有的 `.pull/idlci/idlci.db`，因此作業歷史記錄會延續。僅持有 `serve.lock` 的伺服器會執行作業；另一個（例如同一工作區上的 TUI）則僅排入並顯示它們。作業在其自己的程序組中執行 `idl`（`$CPULL_IDL`、`$IDLCI_IDL`、PATH 上的 `idl` 或 `~/.local/bin/idl`），並設定 `PULL_ROOT`；取消時會向整個程序組發送 SIGTERM，並在 5 秒後發送 SIGKILL。前一個伺服器留下的正在執行中的作業會在啟動時標記為失敗，並終止其程序組。
