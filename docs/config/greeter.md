# Step 8 · Configure greetd

This page configures greetd for the niri session.

## 8.1 Enter the new system

```bash
arch-chroot /mnt
```

## 8.2 Write the config

```bash
mkdir -p /etc/greetd
cat > /etc/greetd/config.toml <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --cmd niri-session"
user = "greeter"
EOF
```

## 8.3 Enable

```bash
systemctl enable greetd
systemctl set-default graphical.target
```

## 8.4 Leave

```bash
exit
```

Press `q`, then run `harch config/shell`.
