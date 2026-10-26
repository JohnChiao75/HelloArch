# Step 9 · Shell

This page sets up bash completion and a few aliases, and optionally
switches the user to zsh.

## 9.1 Enter the new system

```bash
arch-chroot /mnt
```

## 9.2 Bash

```bash
pacman -S --needed bash-completion
cat >> /home/<USER>/.bashrc <<'EOF'
alias ls='ls --color=auto'
alias ll='ls -alF'
alias grep='grep --color=auto'
export EDITOR=vim
EOF
```

Replace `<USER>` with the user you created in step 5.

## 9.3 Optional: zsh

```bash
pacman -S --needed zsh
chsh -s /usr/bin/zsh <USER>
```

## 9.4 Leave

```bash
exit
```

Press `q`, then run `harch end`.
