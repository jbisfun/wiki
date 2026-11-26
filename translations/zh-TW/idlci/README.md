# idlci

為 [idl](https://github.com/jbisfun/idl) 專案的 [pull](https://github.com/jbisfun/pull)
工作區提供本機 CI：一個基於 SQLite 的工作佇列，執行 `idl build|test|lint|fmt --check|check|clean`、
Jenkins 風格的網頁介面、JSON API、git HEAD 監控，以及供代理程式使用的 MCP 伺服器。

```sh
idlci serve [--root DIR] [--addr 127.0.0.1:8737] [--jobs 1] [--watch]   # UI at http://127.0.0.1:8737
idlci mcp                                    # stdio MCP server; starts `idlci serve` when needed
idlci queue fossify-ios/calculator-ios build [TARGET...] [-c release] [--strict] [--wait]
idlci jobs [--status failed] [--project calculator-ios]
idlci log 12 [-f]
idlci cancel 12 / idlci retry 12
```

根目錄為 `--root`，否則為 `$PULL_ROOT`，或最近的包含 `pullfile.plist` 的父目錄。狀態存放於
`$ROOT/.pull/idlci/`（`idlci.db`、`logs/<id>.log`、`serve.addr`、`serve.log`）。工作由專案目錄執行 `idl`，並使用伺服器的環境變數。

API：`GET /api/projects[/{path}]`、`GET|POST /api/jobs`、`GET /api/jobs/{id}`、
`POST /api/jobs/{id}/cancel|retry`、`GET /api/jobs/{id}/log?offset=|tail=`、`GET /api/jobs/{id}/events`（SSE）。
MCP 工具：`projects`、`queue`、`jobs`、`job`、`log`、`wait`、`cancel`、`retry`。
