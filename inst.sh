#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${HARCH_BASE_URL:-https://helloarch.netlify.app}"
BASE_URL="${BASE_URL%/}"
MANIFEST_URL="${HARCH_MANIFEST:-$BASE_URL/docs.list}"

# Prefer the local checkout when this script sits next to harch.py and docs/.
SRC_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  CANDIDATE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$CANDIDATE/harch.py" && -d "$CANDIDATE/docs" ]]; then
    SRC_DIR="$CANDIDATE"
  fi
fi

TMP_DIR=""
cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

if [[ -z "${PREFIX:-}" ]]; then
  if [[ $EUID -eq 0 ]]; then
    PREFIX=/usr/local
  else
    PREFIX="$HOME/.local"
  fi
fi

DOCS_DIR="$PREFIX/share/harch/docs"

if [[ -n "$SRC_DIR" ]]; then
  install -Dm755 "$SRC_DIR/harch.py" "$PREFIX/bin/harch"
  install -d "$DOCS_DIR"
  cp -a "$SRC_DIR/docs/." "$DOCS_DIR/"
else
  if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1"; }
  elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO- "$1"; }
  else
    echo "inst.sh: curl or wget is required for the website install." >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"

  HARCH_TMP="$TMP_DIR/harch.py"
  echo "Downloading $BASE_URL/harch.py ..."
  fetch "$BASE_URL/harch.py" > "$HARCH_TMP"
  if ! grep -q '^#!/usr/bin/env python3' "$HARCH_TMP"; then
    echo "inst.sh: $BASE_URL/harch.py did not look like harch.py." >&2
    exit 1
  fi
  install -Dm755 "$HARCH_TMP" "$PREFIX/bin/harch"

  MANIFEST_TMP="$TMP_DIR/docs.list"
  echo "Downloading $MANIFEST_URL ..."
  fetch "$MANIFEST_URL" > "$MANIFEST_TMP"
  if [[ ! -s "$MANIFEST_TMP" ]]; then
    echo "inst.sh: $MANIFEST_URL is empty." >&2
    exit 1
  fi

  install -d "$DOCS_DIR"
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    rel="${rel%$'\r'}"
    [[ -z "$rel" || "$rel" == \#* ]] && continue
    case "$rel" in
      /*|*..*|*\\*)
        echo "inst.sh: invalid manifest entry: $rel" >&2
        exit 1
        ;;
      *.md) ;;
      *)
        echo "inst.sh: invalid manifest entry: $rel" >&2
        exit 1
        ;;
    esac

    mkdir -p "$DOCS_DIR/$(dirname -- "$rel")"
    PAGE_TMP="$TMP_DIR/page.md"
    fetch "$BASE_URL/docs/$rel" > "$PAGE_TMP"
    if [[ ! -s "$PAGE_TMP" ]]; then
      echo "inst.sh: $BASE_URL/docs/$rel is empty." >&2
      exit 1
    fi
    mv "$PAGE_TMP" "$DOCS_DIR/$rel"
  done < "$MANIFEST_TMP"
fi

echo "Installed harch to $PREFIX/bin/harch"
echo "Docs installed to $DOCS_DIR"

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *) echo "Add $PREFIX/bin to PATH: export PATH=\"$PREFIX/bin:\$PATH\"" ;;
esac

echo "Run: harch beginner"
