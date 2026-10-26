# Step 1 · How to Read This Guide

Welcome to `harch`. This guide installs Arch Linux in small steps.

Every step is a separate file, opened with the `less` pager.

## Moving around

- `j` or `Down` — scroll down one line
- `k` or `Up` — scroll up one line
- `Space` or `f` — next page
- `b` — previous page
- `g` — jump to the top
- `G` — jump to the bottom
- `q` — quit

Keys are case sensitive. `G` is not `g`.

## Going to the next step

When you reach the end of a page, press `q` and run the command it
gives you. The first page is opened with:

```bash
harch beginner
```

- `harch <name>` opens `docs/<name>.md`.
- Do **not** type the `.md` extension.
- `harch` with no name reopens the last file you read.
- On a fresh boot, `harch` with no name opens this page.
- `harch --list` shows every page.

## How to read the commands

1. Run commands in order, top to bottom. Do not skip ahead.
2. Commands are shown without a prompt. You are already root in the
   ISO; do not add `sudo` or a `#` prefix.
3. Text in `<ANGLE BRACKETS>` is a placeholder. Replace it.
4. Disk paths come from variables you set in step 2:
   `ARCH_DISK`, `EFI_PART`, `ROOT_PART`, `SWAP_PART`.
5. Never skip a block marked **WARNING**.
6. If `pacman` asks you to select members of a group, press Enter to
   accept the defaults.

Do not reboot until `end.md`. The guide keeps running from the live
ISO and enters the new system with `arch-chroot` when it needs to.

If a command fails, stop and read the error before continuing.

Ready? Press `q`, then run `harch start`.
