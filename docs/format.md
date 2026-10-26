# Step 4 · Format the Partitions

Formatting writes a fresh filesystem over each partition. It takes a
few seconds and destroys whatever was there before.

> **WARNING:** Every `mkfs` command below erases its target partition.
> Check the variables before each one.

## 4.1 Confirm the targets

```bash
if [ -z "$ARCH_DISK" ]; then
  echo "ARCH_DISK is empty; re-export it from step 2." >&2
fi
echo "disk: $ARCH_DISK"
echo "efi:  $EFI_PART"
echo "root: $ROOT_PART"
echo "swap: $SWAP_PART"
lsblk -f "$ARCH_DISK"
```

Read the output. `ARCH_DISK`, `EFI_PART`, and `ROOT_PART` must be
non-empty. `SWAP_PART` may be empty. `mkfs` with an empty argument
fails harmlessly, but `mkfs` with the *wrong* argument succeeds and
wipes a disk. If any line looks wrong, stop and re-export the
variables.

## 4.2 EFI partition (FAT32)

> **WARNING:** This erases `$EFI_PART`.

```bash
mkfs.fat -F 32 "$EFI_PART"
```

## 4.3 Swap (optional)

Skip this section if `SWAP_PART` is empty.

> **WARNING:** This erases `$SWAP_PART`.

```bash
if [ -n "$SWAP_PART" ] && [ -b "$SWAP_PART" ]; then
  mkswap "$SWAP_PART"
elif [ -n "$SWAP_PART" ]; then
  echo "SWAP_PART=$SWAP_PART is not a block device; skipping swap." >&2
fi
```

The `if` guard skips an empty `SWAP_PART`, and the `-b` test refuses
to format a path that is not a block device. Swap is activated in
step 5, after the system is mounted.

## 4.4 Root partition (ext4)

> **WARNING:** This erases `$ROOT_PART`.

```bash
mkfs.ext4 "$ROOT_PART"
```

`ext4` is the safe default. Btrfs also works, but it needs subvolumes
and a different mount layout — stay on ext4 unless you know why you
are switching.

## 4.5 Verify

```bash
lsblk -f "$ARCH_DISK"
```

Check for:

- `vfat` on the EFI partition
- `ext4` on the root partition
- `swap` on the swap partition (only if you created swap; it is
  activated in step 5)

The filesystems are now empty. Mounting happens in the next step.

Press `q`, then run `harch install/base`.
