#!/usr/bin/env python3
"""harch - page through the helloarch installation guide."""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path

DOCS_ENV = "HARCH_DOCS"
STATE_DIR = Path.home() / ".cache" / "harch"
STATE_FILE = STATE_DIR / "last"


def docs_root() -> Path:
    here = Path(__file__).resolve()
    candidates = []
    env = os.environ.get(DOCS_ENV)
    if env:
        candidates.append(Path(env).expanduser())
    candidates.extend(
        [
            here.parent / "docs",
            here.parent.parent / "share" / "harch" / "docs",
            Path("/usr/local/share/harch/docs"),
            Path.cwd() / "docs",
        ]
    )
    for path in candidates:
        if path.is_dir():
            return path
    sys.exit(f"harch: cannot find the docs directory (set {DOCS_ENV})")


def resolve(name: str) -> Path:
    root = docs_root().resolve()
    rel = name.strip().lstrip("/")
    if rel.endswith(".md"):
        rel = rel[:-3]
    if not rel or rel.startswith("..") or "/../" in rel:
        sys.exit(f"harch: invalid page name: {name!r}")
    path = (root / f"{rel}.md").resolve()
    if root not in path.parents:
        sys.exit(f"harch: page escapes the docs directory: {name!r}")
    if not path.is_file():
        sys.exit(f"harch: no such page: {rel} (try `harch --list`)")
    return path


def page_name(path: Path) -> str:
    return path.resolve().relative_to(docs_root().resolve()).with_suffix("").as_posix()


def list_pages() -> None:
    root = docs_root()
    pages = sorted(p.relative_to(root).with_suffix("").as_posix() for p in root.rglob("*.md"))
    for page in pages:
        print(page)


def open_page(path: Path) -> None:
    pager = os.environ.get("PAGER", "less")
    cmd = shlex.split(pager) or ["less"]
    if Path(cmd[0]).name == "less" and "-R" not in cmd:
        cmd.append("-R")
    cmd.append(str(path))
    try:
        subprocess.run(cmd, check=False)
    except FileNotFoundError:
        sys.exit(f"harch: pager not found: {cmd[0]}")


def save_last(path: Path) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(page_name(path), encoding="utf-8")
    except OSError:
        pass


def usage() -> str:
    return "usage: harch [page|--list]\n       harch <name>   open docs/<name>.md\n       harch          reopen the last page"


def main(argv: list[str]) -> int:
    if len(argv) > 2:
        sys.exit(usage())
    if len(argv) == 2 and argv[1] in ("-l", "--list"):
        list_pages()
        return 0
    if len(argv) == 2 and argv[1] in ("-h", "--help"):
        print(__doc__)
        print(usage())
        return 0
    if len(argv) == 2:
        name = argv[1]
    else:
        name = ""
        if STATE_FILE.is_file():
            try:
                name = STATE_FILE.read_text(encoding="utf-8").strip()
            except OSError:
                name = ""
        if not name or not (docs_root() / f"{name}.md").is_file():
            name = "beginner"
    path = resolve(name)
    open_page(path)
    save_last(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
