# Step 8 · Enable the Display Manager

This page works for both SDDM (Plasma) and GDM (GNOME).

## 8.1 Enter the new system

```bash
arch-chroot /mnt
```

## 8.2 Enable

```bash
if pacman -Q sddm &>/dev/null; then
  systemctl enable sddm
elif pacman -Q gdm &>/dev/null; then
  systemctl enable gdm
else
  echo "Neither sddm nor gdm is installed. Install a desktop first." >&2
fi
systemctl set-default graphical.target
```

## 8.3 Leave

```bash
exit
```

Press `q`, then run `harch config/shell`.
