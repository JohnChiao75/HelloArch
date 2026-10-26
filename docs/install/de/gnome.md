# Step 7 · GNOME

## 7.1 Enter the new system

```bash
arch-chroot /mnt
```

## 7.2 Install

```bash
pacman -S --needed gnome gnome-tweaks
```

`gnome` includes GDM, the login manager.

## 7.3 Leave

```bash
exit
```

Press `q`, then run `harch config/sddm-gdm`.
