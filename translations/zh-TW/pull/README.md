# pull

多儲存庫的 git 包裝工具。`pullfile.plist` 列出各儲存庫、其上游與固定的
commit。每個儲存庫都會複製到 `{pullfile-root}/{repo-name}`。只要一個 `pull commit`，
就會以相同的訊息、身分與簽章，為每個有變更的儲存庫各寫入一個 commit，
然後記錄新的固定點。

## Crate 與功能

pull 是一個 cargo workspace。核心一律會建置；其餘都是 `pull` 執行檔的 cargo 功能
背後的選用 crate，且沒有任何功能需要另一個功能：

    crate          feature        what
    pull-core      (always)       pullfile.plist / local.toml model, identity, path routing
    pull-git       (always)       clone/sync, status, stage, commit across repos, push
                   https, ssh     git transports (git2 features)
    pull-env       env            pullfile `env` + local.toml `[env]`; pull env / pull shell
    pull-hooks     hooks          pullfile `hooks` (precommit, postcommit, pull)
    pull-lint      lint           pullfile `lint`; pull lint
                   conventional   lint `conventional` (Conventional Commits parser)
    pull-ignore    ignore         pullfile `ignore` -> each repo's .git/info/exclude
    pull-worktree  worktree       pull worktree
    pull-launchd   launchd        pullfile `jobs`; pull launchctl / pull session
    pull-mcp       mcp            pull mcp (session/job tools only with `launchd`)

所有功能預設皆啟用。可以用例如以下方式建置較精簡的 pull：

    cargo install --path . --no-default-features --features https,env,hooks

各功能只在執行檔中會合（`src/workspace.rs`）：沒有 `env` 時，hooks、jobs、`each`
與 MCP `exec` 只會取得 PULL_ROOT；沒有 `hooks` 或 `lint` 時，commit 會略過它們；沒有
`launchd` 時，MCP 伺服器就沒有 session 工具。只有 `identity` 與 `repos` 是核心
pullfile 鍵：其他所有頂層鍵都是由對應功能 crate 擁有的區段，當該功能未建置時會原封不動保留
（並回報為已忽略），因此精簡版建置不會丟掉其他建置的設定。`pull --version` 與
`pull status --json`（`features`）會列出執行檔建置時包含的功能。

## 檔案

`pullfile.plist`（共用，會提交）：

    identity: org (selects [orgs.<org>] in local.toml), email = none|local, require_signing
    repos:    [{name, upstream, branch, commit}]
    env:      path, vars                    (feature env)
    lint:     no_description, max_subject_length, conventional, no_trailing_period
                                            (feature lint)
    hooks:    precommit, postcommit, pull   (feature hooks; arrays of `sh -c` commands,
                                            run in the root)
    ignore:   [patterns]                    (feature ignore)
    jobs:     [launchd jobs]                (feature launchd)

Hook 環境變數：PULL_ROOT、PULL_HOOK、PULL_REPOS（以空格分隔）、PULL_MESSAGE（commit hooks）。

`local.toml`（每部機器各自一份，會被 gitignore；找不到時會退回使用 ~/.config/pull/local.toml）：

    name = "jp"
    # email = "..."          # only used if the pullfile says email = "local"
    signing_key = "FPR"      # gpg key; omit to use gpg's default key
    sign = true
    # gpg_program = "gpg"

    [orgs.acme]              # overrides used when the pullfile sets org = "acme"
    name = "jp@acme"
    signing_key = "FPR"

在預設的 `email = none` 下，commit 會寫成 `name <>`，因此不會公開任何電子郵件。

## 指令

    pull init [--org X]            create pullfile.plist and local.toml
    pull repo add URL [--name] [--branch]   |  repo rm NAME  |  repo list
    pull sync                      clone missing repos, fetch, fast-forward to the pins
    pull update                    fast-forward to upstream branches and re-pin
    pull status [--json]           --json: root, features, lint rules, per-repo
                                   branch/head/pin, ahead/behind and changed files
    pull add PATHS...              each path is staged in the repo that contains it
    pull unstage PATHS...          back to HEAD, routed the same way
    pull commit -m MSG [-a] [PATHS...] [--no-verify]
    pull push
    pull lint MSG  |  pull whoami  |  pull each CMD...

如果根目錄本身就是 git 儲存庫，`pull commit` 也會以相同的訊息在那裡提交更新後的 pullfile.plist。

## 忽略

pullfile 的 `ignore` 陣列存放適用於每個儲存庫的 gitignore 模式，例如
`__pycache__/`、`*.pyc`、`.DS_Store`。pull 會在每次執行指令時，將它們保存在各儲存庫的 `.git/info/exclude`
（位於 `# >>> pull ignore` 標記之間），因此儲存庫不需要自己的
.gitignore 項目，也不會為此提交任何內容。這些模式不會取消追蹤已經提交的檔案；
請對那些檔案執行 `git rm --cached`。

## MCP 伺服器

`pull mcp [--root DIR]` 透過 MCP（stdio）向代理程式提供工作區：

    workspace                      repos, branches, pins, ahead/behind, changes, env, jobs
    status / diff / log            per repo or across all repos
    grep / list_files / read_file  ripgrep's engine, .gitignore-aware, confined to the root
    exec                           run a command to completion with the workspace env
    session_new / session_run / session_send / session_capture / session_list /
    session_kill                   stateful terminals (the sessions below); a human can
                                   `pull session attach` to the same one
    job                            start/stop/restart/unload pullfile jobs

將它註冊到代理程式，例如 Hermes：

    hermes mcp add pull --command pull --args mcp --root /path/to/workspace

`pull mcp-servers` 會以 JSON 印出 `pull` 本身，以及 pullfile 中每個 `mcp_servers` 項目
（`{name: {command, args, env}}`，command 會在 `$PATH` 上解析，並設定 `PULL_ROOT`），
讓編輯器或代理程式一次註冊整組伺服器。pullfile 項目只需要 `command`
（預設為鍵名）與 `args`：

    <key>mcp_servers</key>
    <dict>
        <key>radar</key>
        <dict><key>args</key><array><string>mcp</string></array></dict>
    </dict>

ycode-pull 會讀取 `pull mcp-servers`，一次註冊全部伺服器。

## 工作與 session（launchd）

pull 將 launchd 的工作模型（Apple 的 launchd，`liblaunch/launch.h`）移植到工作區。
工作使用 launchd plist 鍵，可放在 pullfile 的 `jobs` 陣列中，或獨立的
`.plist` 檔案裡：

    Label, Program, ProgramArguments, EnvironmentVariables, WorkingDirectory, RunAtLoad,
    KeepAlive (bool or {SuccessfulExit}), StartInterval, ThrottleInterval,
    StandardOutPath, Disabled, LaunchOnlyOnce

每個工作區各有一個常駐程式（`pull launchd`，自動啟動，socket 為 `.pull/launchd.sock`）
負責監督它們。每個工作都在偽終端機中執行，環境為工作區環境（`pull env`）
加上其自身的 EnvironmentVariables 與 `PULL_JOB`，因此每個工作同時也是一個 session。

    pull launchctl load [FILE.plist...]   load pullfile jobs, or launchd plists
    pull launchctl list | print LABEL     (--json for agents)
    pull launchctl start|stop|unload LABEL
    pull launchctl kickstart [-k] LABEL   start, or kill and restart
    pull launchctl shutdown               stop all jobs and the daemon

tmux 風格的 session，供人類與代理程式使用：

    pull session new NAME [-d] [-c DIR] [--keep-alive] [CMD...]   default CMD: $SHELL
    pull session attach NAME              detach with ctrl-\
    pull session ls [--json]              running program + its directory per session
    pull session send NAME [-e] TEXT      type into it (-e: press enter)
    pull session capture NAME [-e]        print its screen (-e: keep colours)
    pull session run NAME CMD...          agents: type CMD, wait for output to settle,
                                          print the screen
    pull session kill NAME

StandardErrorPath 雖然可以接受，但終端機會將 stderr 合併到 stdout，因此兩者都會寫入
StandardOutPath。
