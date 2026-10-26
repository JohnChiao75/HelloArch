# Step 7 · KDE Plasma

## 7.1 Enter the new system

```bash
arch-chroot /mnt
```

## 7.2 Install

```bash
pacman -S --needed plasma-meta konsole dolphin sddm
```

`plasma-meta` pulls in the Plasma desktop. `sddm` is the login
manager; the next page enables it.

## 7.3 Leave

```bash
exit
```

Press `q`, then run `harch config/sddm-gdm`.
