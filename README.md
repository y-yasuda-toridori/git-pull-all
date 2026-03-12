# git-pull-all

指定ディレクトリ配下の全 Git リポジトリに対して、デフォルトブランチへの切替と `git pull --ff-only` を一括実行するシェルスクリプトです。

## 特徴

- デフォルトブランチを自動検出（`origin/HEAD` → `main`/`master`/`develop` → `git remote show`）
- 未コミットの変更や detached HEAD を検出した場合は安全にスキップ
- `--ff-only` による安全な pull（コンフリクトが起きる場合は失敗扱い）
- カラー表示付きの進捗表示とサマリーレポート

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
  Default branch: main  (current: main)
  OK: Updated

========================================
 Summary
========================================
 Total:   5
 Success: 3
 Skipped: 1
 Failed:  1
```

## 動作の流れ

1. 指定ディレクトリ直下の `.git` を持つサブディレクトリを検出
2. 各リポジトリに対して:
   - デフォルトブランチを特定
   - detached HEAD の場合はスキップ
   - 未コミットの変更（staged / unstaged / untracked）がある場合はスキップ
   - デフォルトブランチに切替
   - `git pull --ff-only` を実行
3. 全リポジトリの結果をサマリー表示

## 要件

- Bash 4.0+
- Git
