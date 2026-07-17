#!/bin/bash
# build.sh
#
# Swift ツール群をコンパイルしてバイナリを生成する。
# ビルド完了時に checksums.sha256（4バイナリの SHA-256・コミット対象）を生成する。
#
# Usage: ./build.sh                   # ビルド + checksums 生成
#        ./build.sh --checksums-only  # ビルドせず既存バイナリから checksums のみ再生成
#                                     # （swiftc 不要。全 OS で実行可能）
# 出力先: このスクリプトと同じディレクトリ
#
# 照合は verify-checksums.sh（テスト: .claude/addf/tests/tools/test-binary-checksums.sh）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# checksums 対象バイナリ。verify-checksums.sh の EXPECTED_BINARIES と同期する契約
# （verify 側は checksums.sha256 経由で「登録された名前の照合」に加えて、この allowlist
# 外の実行可能ファイル走査を行う。BINARIES への追加漏れは verify の allowlist 検証で
# ERROR 検出される — Plan 0031 レビュー W7）
BINARIES=(window-info capture-window annotate-grid clip-image)

# SHA-256 ハッシュ計算（sha256sum: Linux/coreutils → shasum -a 256: macOS のフォールバック）
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: sha256sum / shasum のいずれも見つかりません（checksums を生成できない）" >&2
    return 1
  fi
}

# checksums.sha256 を生成する。
# 形式は標準の「<sha256>  <ファイル名>」（パスは checksums.sha256 と同じディレクトリからの
# 相対 = ファイル名のみ）。`shasum -c` / `sha256sum -c` 互換を保つためコメント行は書かない。
generate_checksums() {
  local out="$SCRIPT_DIR/checksums.sha256" tmp f h
  tmp="$(mktemp)"
  for f in "${BINARIES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
      echo "ERROR: $SCRIPT_DIR/$f がありません（ビルド漏れ）" >&2
      rm -f "$tmp"
      return 1
    fi
    h="$(hash_file "$SCRIPT_DIR/$f")" || { rm -f "$tmp"; return 1; }
    printf '%s  %s\n' "$h" "$f" >> "$tmp"
  done
  mv "$tmp" "$out"
  chmod 644 "$out"  # データファイルなので実行可能ビットは落とす（verify の allowlist 走査対象外にする）
  echo "    OK: $out"
}

usage() {
  cat <<'USAGE' >&2
Usage: ./build.sh                   # ビルド + checksums 生成
       ./build.sh --checksums-only  # ビルドせず既存バイナリから checksums のみ再生成
       ./build.sh -h | --help       # このヘルプを表示
USAGE
}

case "${1:-}" in
  '') ;;
  --checksums-only)
    echo "==> Generating checksums.sha256 (checksums only)..."
    generate_checksums
    exit 0
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: 未知の引数: $1" >&2
    usage
    exit 1
    ;;
esac

echo "==> Building window-info..."
swiftc "$SCRIPT_DIR/window-info.swift" -o "$SCRIPT_DIR/window-info" \
    -framework ApplicationServices -framework Foundation
echo "    OK: $SCRIPT_DIR/window-info"

echo "==> Building capture-window..."
swiftc "$SCRIPT_DIR/capture-window.swift" -o "$SCRIPT_DIR/capture-window" \
    -framework ScreenCaptureKit -framework CoreGraphics -framework Foundation
echo "    OK: $SCRIPT_DIR/capture-window"

echo "==> Setting execute permission on check-screen-recording.sh..."
chmod +x "$SCRIPT_DIR/check-screen-recording.sh"
echo "    OK: $SCRIPT_DIR/check-screen-recording.sh"

echo "==> Building annotate-grid..."
swiftc "$SCRIPT_DIR/annotate-grid.swift" -o "$SCRIPT_DIR/annotate-grid" \
    -framework CoreGraphics -framework CoreText -framework Foundation -framework ImageIO
echo "    OK: $SCRIPT_DIR/annotate-grid"

echo "==> Building clip-image..."
swiftc "$SCRIPT_DIR/clip-image.swift" -o "$SCRIPT_DIR/clip-image" \
    -framework CoreGraphics -framework Foundation -framework ImageIO
echo "    OK: $SCRIPT_DIR/clip-image"

echo "==> Generating checksums.sha256..."
generate_checksums

echo ""
echo "Build complete."
