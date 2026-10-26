# Step 2 · Network, Mirrors, and Disk Variables

You need a working internet connection and a clear idea of which
disk you will erase.

## 2.1 Check the boot mode, clock, and connection

This guide is UEFI-only. Confirm the ISO booted in UEFI mode:

```bash
ls /sys/firmware/efi/efivars >/dev/null 2>&1 \
  && echo "UEFI mode" \
  || echo "BIOS/CSM mode: reboot the ISO in UEFI mode"
```

If you see the BIOS/CSM message, reboot the ISO and pick the UEFI
entry. Do not continue.

Set the clock and keyboard:

```bash
timedatectl set-ntp true
loadkeys us
```

Replace `us` with your keymap if needed (`de`, `fr`, `jp106`, ...).
A wrong clock breaks HTTPS and package signatures; a wrong keymap
makes passphrases and `yes` confirmations hard to type.

Now check the connection:

```bash
ping -c 3 archlinux.org
```

If ping fails with `Name or service not known`, DNS is the problem;
try `ping -c 3 1.1.1.1` before changing the link.

If replies come back, skip to 2.3.

## 2.2 Connect

### Ethernet

Wired networking is usually automatic. If ping failed, list the
interfaces:

```bash
ip link
```

Find your interface name (for example `enp3s0`), then replace
`<IFACE>` and run:

```bash
dhcpcd <IFACE>
```

`dhcpcd` is included in the ISO, but the ISO normally uses
`systemd-networkd`. If `dhcpcd` complains that the interface is
already configured, check `networkctl status <IFACE>` or restart
`systemd-networkd` instead:

```bash
systemctl restart systemd-networkd
```

### Wi-Fi with iwctl

```bash
iwctl
```

Inside the `[iwd]#` prompt, replace `<DEVICE>` with the name from
`device list`:

```text
device list
station <DEVICE> scan
station <DEVICE> get-networks
station <DEVICE> connect "<SSID>"
```

Enter the passphrase when asked, then:

```text
exit
```

If no wireless device appears, check for a hardware switch:

```bash
rfkill list
rfkill unblock wifi
```

Run `ping -c 3 archlinux.org` again to confirm.

## 2.3 Faster mirrors

The mirrorlist decides where packages come from. A slow mirror makes
the whole install slow.

Back it up first:

```bash
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
```

Then generate a ranked list with `reflector` (it is included in the
ISO). Replace `US` with your country code:

```bash
CC=US
reflector --country "$CC" --protocol https --age 12 \
  --sort rate --save /etc/pacman.d/mirrorlist \
  || cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
grep -q '^Server' /etc/pacman.d/mirrorlist \
  || cp /etc/pacman.d/mirrorlist.bak /etc/pacman.d/mirrorlist
```

If `reflector` still fails, edit the list by hand:

```bash
nano /etc/pacman.d/mirrorlist
```

Move one nearby `Server = ...` line to the top. Save with `Ctrl+O`,
press Enter to confirm the filename, then exit with `Ctrl+X`.

Refresh the package databases:

```bash
pacman -Syy
```

This mirrorlist is for the live environment and is copied into the
new system in step 5. You can re-rank it in `install/extra`.

## 2.4 Set your device variables

Every later disk command uses shell variables, so a partition-number
typo cannot silently hit another disk. The variables do **not** catch
a wrong `ARCH_DISK`, so confirm the disk first:

```bash
lsblk -d -o NAME,SIZE,MODEL
```

Pick the disk you intend to erase. Run **one** of these blocks.

NVMe:

```bash
export ARCH_DISK=/dev/nvme0n1
```

SATA, USB, or virtual disk:

```bash
export ARCH_DISK=/dev/sda
```

Then set the partition names:

```bash
case "$ARCH_DISK" in
  *nvme*|*mmcblk*) SEP=p ;;
  *)               SEP= ;;
esac

export EFI_PART="${ARCH_DISK}${SEP}1"
export ROOT_PART="${ARCH_DISK}${SEP}2"
export SWAP_PART=
```

Swap is optional and off by default. If you want it, uncomment both
lines. Swap becomes `p2`/`2`, and root moves to `p3`/`3`; step 3
creates swap before root:

```bash
# export SWAP_PART="${ARCH_DISK}${SEP}2"
# export ROOT_PART="${ARCH_DISK}${SEP}3"
```

Verify:

```bash
echo "disk: $ARCH_DISK"
echo "efi:  $EFI_PART"
echo "root: $ROOT_PART"
echo "swap: $SWAP_PART"
lsblk "$ARCH_DISK"
```

`lsblk` must show the disk you intend to erase. If it does not, fix
the variables before going further.

Notes:

- `export` makes the variables visible to every command in this
  shell, including `harch`. A new TTY or a reboot forgets them.
- The partition variables are just names for now. The devices appear
  after you partition in step 3.
- Do not reboot until `end.md`; the guide continues in this live
  environment.

Press `q`, then run `harch part`.
