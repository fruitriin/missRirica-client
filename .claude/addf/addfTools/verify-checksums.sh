#!/bin/bash
# verify-checksums.sh
#
# コミット済みバイナリと checksums.sha256 の SHA-256 照合（Plan 0031）。
# ハッシュ計算のみでバイナリを実行しないため、非 macOS を含む全 OS で動作する。
#
# Usage: verify-checksums.sh [tools_dir]
#   tools_dir 省略時はこのスクリプトのあるディレクトリを照合対象にする。
#
# exit code（addfTools 3値規約）:
#   0 = 照合 OK（または downstream で checksums 不在の正当な SKIP）
#   1 = ERROR: ハッシュ不一致 / バイナリ不在 / upstream で checksums 不在 / ハッシュツール不在
#   2 = WARNING: repo_kind 判定不能で checksums 不在（SKIP + 種別シグナルの整備を促す）
#
# checksums 不在時のセマンティクス（Plan 0031 未決事項の決定）:
#   - upstream（ADDF 本体）: ERROR — 本体では build.sh が生成・コミットするため、
#     不在はビルド漏れか削除ドリフト
#   - downstream: SKIP（必ず明示出力する。silent 無効化にしない）— checksums 導入前の
#     旧バージョン配布には存在せず、配布状態という環境起因のため
#   - repo_kind 判定は「存在≠所有」原則に従い、CLAUDE.repo.md の種別宣言（一次）→
#     .claude/addf/lock.json の存在（フォールバック = downstream）の明示シグナルで行う。
#     lint-template-sync.py detect_repo_kind() の bash ミラー（判定仕様を変えるときは両方更新）
#
# 攻撃者モデル対策（Plan 0031 レビュー Critical）:
#   - checksums.sha256 の name 列を allowlist とし、TOOLS_DIR 内の実行可能ファイル走査で
#     allowlist 外の実行可能ファイル（例: 攻撃者が紛れ込ませた evil-tool）を検出したら ERROR
#   - name フィールドのパスセパレータ・パストラバーサル・空文字列は ERROR で拒否（`actual: <hash>`
#     の漏洩を防ぐ）
#   - build.sh の BINARIES 配列と本スクリプトの EXPECTED_BINARIES は「build.sh が生成するので
#     checksums.sha256 に載る名前 = BINARIES」の契約により同期する（両方に allowlist を持つ）

set -uo pipefail

# build.sh の BINARIES 配列と同期する allowlist（両方に持つことで片側追加漏れを ERROR で拾う）。
# BINARIES 追加時: verify 側は checksums.sha256 経由で自動追従するが、未登録実行可能ファイル
# の検出には本 allowlist が必要。build.sh の BINARIES と本配列は同期する（片方に追加を忘れると
# checksums の name 検証か未登録ファイル走査のいずれかが ERROR で FAIL する）
EXPECTED_BINARIES="window-info capture-window annotate-grid clip-image"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "${1:-$SCRIPT_DIR}" && pwd)"
PROJECT_DIR="$(cd "$TOOLS_DIR/../../.." && pwd)"
SUMS="$TOOLS_DIR/checksums.sha256"

# SHA-256 ハッシュ計算（sha256sum: Linux/coreutils → shasum -a 256: macOS のフォールバック）
if command -v sha256sum >/dev/null 2>&1; then
  hash_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  hash_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  # 照合できないのに成功を装わない（run-all.sh 設計ガイドライン: 必須ランタイム不在 ≠ SKIP）
  echo "ERROR: sha256sum / shasum のいずれも見つかりません（照合を実行できない）"
  exit 1
fi

# コードフェンス（``` / ~~~）内を除去して stdout に返す
strip_fences() {
  awk '
    { s = $0; sub(/^[ \t]+/, "", s) }
    fence != "" { if (index(s, fence) == 1) fence = ""; next }
    substr(s, 1, 3) == "```" || substr(s, 1, 3) == "~~~" { fence = substr(s, 1, 3); next }
    { print }
  '
}

# upstream / downstream / unknown を返す（詳細はヘッダコメント参照）
#
# 同期契約: lint-template-sync.py の detect_repo_kind() と挙動を同期する契約。
# 判定仕様（一次: CLAUDE.repo.md の種別宣言＋@メンション1段解決／フォールバック: addf-lock.json）
# を変えるときは Python 側も同時に更新する（lint-template-sync.py のペア7が本契約文言の
# 存在を機械保証する — sync-lint-design.md のパターン）。
#
# @メンションの空白扱い: Python 側は行全体を re.match(r'@(\S+\.md)$', s.strip()) 相当で判定し
# 空白を strip する。bash 側もここで行全体の前後空白を除去してから @xxx.md 判定に入る
# （多段 @メンションの再帰は行わない — 双方 depth=1 に固定して DoS/循環参照を避ける）。
#
# パストラバーサル耐性（Plan 0043 項目4・ペア7 同期契約）: `..` を含むパス・絶対パス・
# シンボリックリンク経由の脱出は silent に無視する（PROJECT_DIR 配下に realpath で
# 収まらないものは解決対象にしない）。Python 側の _safe_resolve_mention() と同じガード。
detect_repo_kind() {
  local text="" line inc trimmed resolved base_real
  base_real="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)"
  if [ -f "$PROJECT_DIR/CLAUDE.repo.md" ]; then
    text="$(strip_fences < "$PROJECT_DIR/CLAUDE.repo.md")"
    # 行全体が @xxx.md の @メンションを1段だけ解決する
    # heredoc は多段再帰させないため（Python 側と揃えて depth=1 に固定）ここでは単純に text
    # を行単位で舐めるだけに留める。ネストした @xxx.md はさらに解決しない
    while IFS= read -r line; do
      # Python 側の s.strip() と揃えて行全体の前後空白を除去してから判定する
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      inc="${trimmed#@}"
      # @xxx.md 形式でファイル存在、かつパストラバーサルガード通過のみ解決
      if [ "$trimmed" != "$inc" ] && printf '%s' "$inc" | grep -Eq '^[^[:space:]]+\.md$' \
         && ! printf '%s' "$inc" | grep -Eq '(^|/)\.\.(/|$)' \
         && [ "${inc:0:1}" != "/" ] \
         && [ -f "$PROJECT_DIR/$inc" ]; then
        # realpath で PROJECT_DIR 配下に収まることを検査（シンボリックリンク脱出防止）
        resolved="$(cd "$PROJECT_DIR" 2>/dev/null && cd "$(dirname "$inc")" 2>/dev/null && pwd -P)/$(basename "$inc")"
        if [ -n "$base_real" ] && { [ "$resolved" = "$base_real/$(basename "$inc")" ] \
             || case "$resolved" in "$base_real"/*) true ;; *) false ;; esac; }; then
          text="$text
$(strip_fences < "$PROJECT_DIR/$inc")"
        fi
      fi
    done <<EOF_LINES
$text
EOF_LINES
  fi
  local up=0 down=0
  printf '%s' "$text" | grep -qF '**ADDF 開発プロジェクト**' && up=1
  printf '%s' "$text" | grep -qF '**ADDF 利用プロジェクト**' && down=1
  if [ "$up" -eq 1 ] && [ "$down" -eq 0 ]; then echo upstream; return; fi
  if [ "$down" -eq 1 ] && [ "$up" -eq 0 ]; then echo downstream; return; fi
  # 両方ヒット（混在 = 判定不能・安全側）と宣言なしは lock フォールバックに委ねる
  if [ -f "$PROJECT_DIR/.claude/addf/lock.json" ]; then echo downstream; else echo unknown; fi
}

if [ ! -f "$SUMS" ]; then
  kind="$(detect_repo_kind)"
  case "$kind" in
    upstream)
      echo "ERROR: checksums.sha256 が不在（repo_kind=upstream。ADDF 本体では build.sh が生成・コミットする — ビルド漏れか削除ドリフト。復旧: bash .claude/addf/addfTools/build.sh --checksums-only）"
      exit 1
      ;;
    downstream)
      echo "SKIP: checksums.sha256 不在（repo_kind=downstream。checksums 導入前の配布の可能性 — addf-migrate で最新化すると照合できる）"
      exit 0
      ;;
    *)
      echo "SKIP: checksums.sha256 不在・repo_kind 判定不能（WARNING）。ダウンストリームなら CLAUDE.repo.md に種別宣言（このリポジトリは **ADDF 利用プロジェクト** です。）を書くか .claude/addf/lock.json を配置する"
      exit 2
      ;;
  esac
fi

fail=0
checked=0
# 登録済み name の記録（allowlist 外の実行可能ファイル検出に使う）
registered=" "
# `while read -r expected name` は $name の残余をすべて拾う（ファイル名にスペースが
# 混じる将来変更の安全網。現状の4種にスペースはないが、`_` にスプリット余剰を捨てて
# しまうと後方で空白名との識別ができない）
while read -r expected name; do
  # 空行と（手書きされた場合の）コメント行は読み飛ばす
  [ -z "${expected:-}" ] && continue
  case "$expected" in '#'*) continue ;; esac
  # name の健全性検証（`actual: <hash>` の漏洩防止・パストラバーサル防止）
  if [ -z "${name:-}" ]; then
    echo "ERROR: checksums.sha256 の行に name フィールドが空 — 拒否: $expected"
    exit 1
  fi
  case "$name" in
    */*|*..*)
      echo "ERROR: checksums.sha256 の name にパスセパレータまたは .. を検出 — 拒否: $name"
      exit 1
      ;;
  esac
  # BINARIES allowlist 外の name は拒否（build.sh の BINARIES と本 EXPECTED_BINARIES の
  # 同期契約に反する — 片方に無い名前は checksums に載せない）
  name_ok=0
  for allowed in $EXPECTED_BINARIES; do
    [ "$name" = "$allowed" ] && name_ok=1 && break
  done
  if [ "$name_ok" -ne 1 ]; then
    echo "ERROR: checksums.sha256 の name '$name' が BINARIES allowlist ($EXPECTED_BINARIES) に無い — 拒否"
    exit 1
  fi
  registered="$registered$name "
  if [ ! -f "$TOOLS_DIR/$name" ]; then
    echo "FAIL: $name — バイナリが不在（checksums.sha256 には記載あり）"
    echo "      復旧: バイナリを再ビルド（bash $TOOLS_DIR/build.sh）または削除前の状態に復元。"
    echo "            復旧後に本スクリプトを再実行して照合が通ることを確認する"
    fail=1
    continue
  fi
  actual="$(hash_file "$TOOLS_DIR/$name")"
  if [ "$actual" = "$expected" ]; then
    echo "OK: $name"
  else
    echo "FAIL: $name — ハッシュ不一致（バイナリだけ/checksums だけの片側コミット、または改変の疑い）"
    echo "      expected: $expected"
    echo "      actual:   $actual"
    echo "      復旧: 片側コミットの疑いなら該当バイナリを再ビルド（bash $TOOLS_DIR/build.sh）"
    echo "            または元に戻す。改竄疑いならソース差分・コミット履歴を確認する"
    fail=1
  fi
  checked=$((checked + 1))
done < "$SUMS"

if [ "$checked" -eq 0 ] && [ "$fail" -eq 0 ]; then
  echo "ERROR: checksums.sha256 に照合対象が1件もありません"
  exit 1
fi

# TOOLS_DIR 内の実行可能ファイル走査 — allowlist（EXPECTED_BINARIES）と registered の
# いずれにも無い実行可能ファイルは「未登録バイナリ」として ERROR。攻撃者が evil-tool を
# 紛れ込ませても本チェックで FAIL する
for f in "$TOOLS_DIR"/*; do
  [ -f "$f" ] || continue
  [ -x "$f" ] || continue
  base="$(basename "$f")"
  # ビルド・照合スクリプト自身は実行可能で正当（allowlist 対象外）
  case "$base" in
    build.sh|verify-checksums.sh|check-screen-recording.sh) continue ;;
    *.sh|*.py) continue ;;
  esac
  # allowlist 内で registered のバイナリはスキップ
  case " $registered" in
    *" $base "*) continue ;;
  esac
  in_allowlist=0
  for allowed in $EXPECTED_BINARIES; do
    [ "$base" = "$allowed" ] && in_allowlist=1 && break
  done
  # allowlist にあるが registered に無い（= checksums.sha256 に登録漏れ）→ ERROR
  # allowlist にも無い（= 未登録の外部混入）→ ERROR
  if [ "$in_allowlist" -eq 1 ]; then
    echo "ERROR: 未登録バイナリ検出 — $base は BINARIES allowlist にあるが checksums.sha256 に登録されていない（片側コミット疑い）"
  else
    echo "ERROR: 未登録バイナリ検出 — $base は BINARIES allowlist ($EXPECTED_BINARIES) に無い実行可能ファイル（外部混入疑い）"
  fi
  fail=1
done

exit "$fail"
