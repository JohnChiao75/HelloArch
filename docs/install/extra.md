# Step 6 · Extra Packages

These packages are optional but useful. Run them inside the new
system.

## 6.1 Enter the new system

```bash
arch-chroot /mnt
```

## 6.2 Install

```bash
pacman -Syu --needed base-devel git htop man-db reflector pacman-contrib
```

`base-devel` is needed to build AUR packages later. `git` is for
dotfiles. `pacman-contrib` provides `paccache`.

Enable the weekly TRIM timer if you have an SSD:

```bash
systemctl enable fstrim.timer
```

Re-rank the new system's mirrorlist (replace `US`):

```bash
CC=US
reflector --country "$CC" --protocol https --age 12 \
  --sort rate --save /etc/pacman.d/mirrorlist
```

Leave the chroot:

```bash
exit
```

## 6.3 Pick a desktop

Choose one:

- `harch install/de/plasma` — KDE Plasma
- `harch install/de/gnome` — GNOME
- `harch install/de/niri-dux` — niri (keyboard-driven Wayland)

Press `q`, then run one of the commands above.
