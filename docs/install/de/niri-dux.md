# Step 7 · niri

niri is a scrollable-tiling Wayland compositor. This page installs a
minimal session: niri, a terminal, a launcher, and greetd.

If you use a personal `dux` dotfiles set, copy it into `~/.config`
after the first login; this page does not install any dotfiles.

## 7.1 Enter the new system

```bash
arch-chroot /mnt
```

## 7.2 Install

```bash
pacman -S --needed niri xwayland-satellite foot fuzzel \
  xdg-desktop-portal-gtk polkit \
  pipewire pipewire-pulse wireplumber \
  greetd greetd-tuigreet
```

## 7.3 First config

Create a minimal niri config so the session starts with a terminal
and a launcher. Replace `<USER>` with your user name:

```bash
mkdir -p /home/<USER>/.config/niri
cat > /home/<USER>/.config/niri/config.kdl <<'EOF'
input {
    keyboard {
        xkb { layout "us" }
    }
}

spawn-at-startup "foot"

binds {
    Mod+T { spawn "foot"; }
    Mod+D { spawn "fuzzel"; }
    Mod+Shift+E { quit; }
}
EOF
chown -R <USER>: /home/<USER>/.config/niri
```

Change the `xkb` layout if you do not use `us`.

## 7.4 Leave

```bash
exit
```

Press `q`, then run `harch config/greeter`.
