# git-pull-all

指定ディレクトリ配下の全 Git リポジトリに対して、デフォルトブランチへの切替と `git pull --ff-only` を一括実行するシェルスクリプトです。

## 特徴

- デフォルトブランチを自動検出（`origin/HEAD` → `main`/`master`/`develop` → `git remote show`）
- 未コミットの変更や detached HEAD を検出した場合は安全にスキップ
- `--ff-only` による安全な pull（コンフリクトが起きる場合は失敗扱い）
- pull 後に元のブランチへ自動復帰（作業ブランチを維持）
- カラー表示付きの進捗表示とサマリーレポート（各リポジトリの現在ブランチ付き）

## 使い方

```bash
# カレントディレクトリ配下の全リポジトリを更新
cd /path/to/parent
./git-pull-all.sh

# 引数でディレクトリを指定
./git-pull-all.sh /path/to/parent
```

## 出力例

```
========================================
 Git Pull All Repositories
 Target: /home/user/dev
========================================

Found 5 git repositories

[1/5] project-a
  Default branch: main  (current: main)
  OK: Already up to date

[2/5] project-b
  Default branch: main  (current: feature/xyz)
  WARNING: Uncommitted changes detected -- skipping

[3/5] project-c
  Default branch: main  (current: feature/abc)
  OK: Updated
  Restored branch: feature/abc

[4/5] project-d
  Default branch: main  (current: main)
  OK: Already up to date

========================================
 Summary
========================================
 Total:   5
 Success: 3
 Skipped: 1
 Failed:  1

  OK      project-a (main) [main] -- already up to date
  SKIP    project-b [feature/xyz] -- uncommitted changes
  OK      project-c (main) [feature/abc] -- updated
  OK      project-d (main) [main] -- already up to date
  FAIL    project-e (main) [develop] -- pull failed
```

## 動作の流れ

1. 指定ディレクトリ直下の `.git` を持つサブディレクトリを検出
2. 各リポジトリに対して:
   - デフォルトブランチを特定
   - detached HEAD の場合はスキップ
   - 未コミットの変更（staged / unstaged / untracked）がある場合はスキップ
   - デフォルトブランチに切替
   - `git pull --ff-only` を実行
   - 元のブランチに復帰
3. 全リポジトリの結果をサマリー表示（各リポジトリの現在ブランチ `[branch]` 付き）

## 要件

- Bash 4.0+
- Git
