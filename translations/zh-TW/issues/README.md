# issues

以 [radar](https://github.com/jbisfun/radar) 提交的報告。每份報告都記錄儲存庫、檔案、行號、該行的文字、備註與提交時間。

- `radar.db/`：PoloDB 資料庫，是事實來源。
- `docs/`：每份未結報告一頁，外加 `index.md`，由 pull precommit hook 中的 `radar export` 產生。它已被 gitignore；由 wiki 發布。
