#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
DOCS_DIR="$PREFIX/share/harch/docs"

if [[ ! -f "$SRC_DIR/harch.py" || ! -d "$SRC_DIR/docs" ]]; then
  echo "inst.sh: run this from the helloarch repository root." >&2
  exit 1
fi

install -Dm755 "$SRC_DIR/harch.py" "$PREFIX/bin/harch"
install -d "$DOCS_DIR"
cp -a "$SRC_DIR/docs/." "$DOCS_DIR/"

echo "Installed harch to $PREFIX/bin/harch"
echo "Docs installed to $DOCS_DIR"
echo "Run: $PREFIX/bin/harch beginner"
