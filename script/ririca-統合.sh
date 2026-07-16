#!/usr/bin/env fish
# ririca-main を misskey/develop 最新から再生成する統合スクリプト
# MISTEMS の main-統合.sh と同じ戦略:
#   - 統合ブランチは使い捨て。misskey/develop に reset --hard してから機能ブランチを squash merge
#   - コンフリクト解消は git rerere に記憶させる（~/.gitconfig で rerere.enabled=true にすること）
#   - CHANGELOG.md のコンフリクトは毎回破棄
#
# 前提:
#   - submodule misskey/ が初期化済みで、リモートが以下の構成:
#       origin   = Ririca 用 standalone リポジトリ（機能ブランチ ririca/* の置き場）
#       upstream = https://github.com/misskey-dev/misskey.git
#   - 実行場所: missRirica-client リポジトリのルート

cd misskey; or begin
    echo "misskey/ submodule が見つかりません" >&2
    exit 1
end

git fetch origin
git fetch upstream

# ブランチ存在チェック付き squash merge（main-統合.sh より移植）
function squash_merge
    set -l branch $argv[1]
    if not command git rev-parse --verify $branch >/dev/null 2>&1
        echo "エラー: ブランチ '$branch' が見つかりません。スクリプトを終了します。" >&2
        exit 1
    end
    command git merge --squash $branch
    # CHANGELOG.md は毎回破棄するので、コンフリクト判定の前に解消
    command git checkout HEAD -- CHANGELOG.md 2>/dev/null
    # CHANGELOG.md 以外にコンフリクトがあったらストップ
    if command git status --porcelain | grep -q "^U"
        echo "コンフリクトが発生しました ($branch)。手動で解決してください。"
        echo "解決が完了したら 'Y' を入力してください（それ以外は終了します）: "
        read -l response
        if test "$response" != "Y"
            echo "スクリプトを終了します。"
            exit 1
        end
    end
end

git switch ririca-main; or git switch -c ririca-main
git reset upstream/develop --hard

# ==== 機能ブランチ（依存順） ====================================
# 各ブランチは upstream/develop に対して rebase 済みであること。
# コンフリクトが繰り返される場合はコミットを1つに圧縮して rerere に覚えさせる。

squash_merge origin/ririca/instance-origin-decouple
git commit -a -m "apiUrl/wsOrigin を instance_url メタ由来にし、未ログイン時の起動をガード"

squash_merge origin/ririca/standalone-frontend
git commit -a -m "frontend をシェルから読み込める静的バンドルとしてビルド可能に（SW無効化・locale同梱）"

squash_merge origin/ririca/token-signin
git commit -a -m "アクセストークン/MiAuth によるサインイン導線"

squash_merge origin/ririca/native-hooks
git commit -a -m "window.__ririca ブリッジ規約の汎用フックポイント"

squash_merge origin/ririca/push-hooks
git commit -a -m "push 購読をフック経由で外部（シェル側）に委譲"

squash_merge origin/ririca/mobile-ui
git commit -a -m "モバイル向け UI 小改修"

# ==== バージョンスタンプ =========================================
set RIRICAVER 0 # 統合のたびにインクリメント
set file_path "package.json"
set current_version (jq -r '.version' $file_path)
set new_version "$current_version-ririca.$RIRICAVER"

jq --arg new_version "$new_version" '.version = $new_version' $file_path > tmp.json && mv tmp.json $file_path
npx prettier -w $file_path

echo "Version updated to: $new_version"
git commit -a -m "Version updated to: $new_version"
git tag -a "$new_version" -m "ririca.$RIRICAVER"
