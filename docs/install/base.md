# Step 5 · Install the Base System

This page mounts the new system, installs the base packages, writes
`fstab`, configures the system inside `arch-chroot`, and installs
GRUB.

Do not reboot yet. The guide continues in the live environment;
later pages tell you to enter `arch-chroot /mnt` when they need to.

## 5.1 Mount

```bash
mount "$ROOT_PART" /mnt
mount --mkdir "$EFI_PART" /mnt/boot
if [ -n "$SWAP_PART" ] && ! grep -q "^$SWAP_PART " /proc/swaps; then
  swapon "$SWAP_PART"
fi
```

Confirm:

```bash
lsblk -f "$ARCH_DISK"
findmnt /mnt
```

## 5.2 Install the base packages

Pick the microcode for your CPU: `intel-ucode` or `amd-ucode`.

```bash
UCODE=intel-ucode   # or amd-ucode
pacstrap -K /mnt base linux linux-firmware "$UCODE" \
  networkmanager sudo vim
```

`-K` initialises the pacman keyring in the new root. This can take a
few minutes.

## 5.3 Write fstab

```bash
genfstab -U /mnt >> /mnt/etc/fstab
cat /mnt/etc/fstab
```

Check that the root, EFI, and swap entries look right before
continuing.

Carry the ranked mirrorlist into the new system:

```bash
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
```

## 5.4 Configure the system

Enter the new system:

```bash
arch-chroot /mnt
```

Timezone (replace `Region/City`):

```bash
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
```

Locale:

```bash
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
```

Keyboard (replace `us` if needed):

```bash
echo 'KEYMAP=us' > /etc/vconsole.conf
```

Hostname (replace `<HOSTNAME>`):

```bash
MYHOST=<HOSTNAME>
echo "$MYHOST" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $MYHOST.localdomain $MYHOST
EOF
```

Root password:

```bash
passwd
```

Create your user (replace `<USER>`):

```bash
NEWUSER=<USER>
useradd -m -G wheel -s /bin/bash "$NEWUSER"
passwd "$NEWUSER"
```

Allow the `wheel` group to use `sudo`:

```bash
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
```

Enable networking and time sync:

```bash
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
```

## 5.5 Install GRUB

```bash
pacman -S --needed grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot \
  --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
```

Leave the chroot:

```bash
exit
```

Do **not** reboot. The next page adds packages and a desktop.

Press `q`, then run `harch install/extra`.
