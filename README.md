# helloarch

A step-by-step Arch Linux installation guide, read with `harch`.

## What this is

`harch` is a tiny pager wrapper. It opens `docs/<page>.md` in `less`
and remembers the last page you read. The guide is UEFI-only and uses
`cfdisk`, ext4, GRUB, and NetworkManager.

## Install from the repo

```bash
bash inst.sh
harch beginner
```

Run it as root; the live ISO shell is already root, so `sudo` is not
required. If you are a normal user, use `sudo bash inst.sh`.

The installer copies `harch.py` to `/usr/local/bin/harch` and
`docs/` to `/usr/local/share/harch/docs`. If you cannot write to
`/usr/local`, install into your home directory:

```bash
PREFIX="$HOME/.local" bash inst.sh
export PATH="$HOME/.local/bin:$PATH"
harch beginner
```

## Usage

```bash
harch beginner        # open a page
harch install/base    # subdirectories work; do not add .md
harch                 # reopen the last page
harch --list          # list every page
```

Set `HARCH_DOCS` to point at a different docs directory, and `PAGER`
to use a different pager.

## Requirements

- Arch Linux live ISO, booted in UEFI mode
- Python 3
- `less`

## Doc map

- `beginner` — how to read the guide
- `start` — boot mode, network, mirrors, disk variables
- `part` — partition with cfdisk
- `format` — mkfs
- `install/base` — mount, pacstrap, chroot, GRUB
- `install/extra` — extra packages
- `install/de/plasma` — KDE Plasma
- `install/de/gnome` — GNOME
- `install/de/niri-dux` — niri
- `config/sddm-gdm` — enable SDDM or GDM
- `config/greeter` — configure greetd for niri
- `config/shell` — bash completion, aliases, optional zsh
- `end` — unmount and reboot
