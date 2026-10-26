# Step 3 · Partition the Disk with cfdisk

> **WARNING:** This step erases data. Everything on the disk you
> select will be gone. There is no undo, no recycle bin, no recovery.

If the disk holds anything you care about, stop now and back it up.
This guide assumes a dedicated disk. If you need to keep another
operating system, stop; this page does not support dual-boot.

## 3.1 Check the variables

The device paths were exported in step 2. Confirm them first:

```bash
echo "disk: $ARCH_DISK"
echo "efi:  $EFI_PART"
echo "root: $ROOT_PART"
echo "swap: $SWAP_PART"
lsblk "$ARCH_DISK"
```

`ARCH_DISK`, `EFI_PART`, and `ROOT_PART` must print a device path.
`SWAP_PART` may be empty; that means no swap.

A new terminal or a reboot clears these variables. Re-export them
from step 2.

## 3.2 Plan the layout (UEFI)

- `$EFI_PART` — 512M — EFI System
- `$SWAP_PART` — optional — Linux swap
- `$ROOT_PART` — rest — Linux filesystem

If `SWAP_PART` is set, create swap **before** root so the numbers
line up: EFI is `1`, swap is `2`, root is `3`. Without swap, root is
`2`.

For hibernation, make swap at least as large as your RAM. Otherwise
4G is enough for most systems. Hibernation also needs a `resume=`
kernel parameter and an initramfs `resume` hook; this guide does not
set those up.

## 3.3 Partition with cfdisk

`cfdisk --zero` starts from an empty in-memory table instead of
reading the old one. When you write, the old partition table is
replaced. That is what we want on a dedicated disk.

> **WARNING:** `cfdisk` writes directly to `$ARCH_DISK`. Read the
> header line in cfdisk and confirm it names the right disk.

```bash
if [ -z "$ARCH_DISK" ]; then
  echo "ARCH_DISK is empty; re-export it from step 2." >&2
else
  cfdisk --zero "$ARCH_DISK"
fi
```

Then:

1. If asked for a label type, choose `gpt`.
2. Select `Free space`, choose `New`, type `512M`, press Enter.
3. With the new partition selected, choose `Type`, pick `EFI System`.
4. If `SWAP_PART` is set: select the remaining free space, choose
   `New`, type the swap size (for example `4G` or your RAM size),
   press Enter. Choose `Type`, pick `Linux swap`.
5. Select the remaining free space, choose `New`, accept the full
   size, press Enter. This is root.
6. Choose `Write`, type `yes`, press Enter.
7. Choose `Quit`.

Tell the kernel about the new table:

```bash
partprobe "$ARCH_DISK"
udevadm settle
```

## 3.4 Verify

```bash
lsblk -f "$ARCH_DISK"
```

You should see the partitions you just made, with no filesystem on
them yet. The numbers must match the variables:

- no swap: `EFI_PART` is `...1`, `ROOT_PART` is `...2`
- with swap: `EFI_PART` is `...1`, `SWAP_PART` is `...2`,
  `ROOT_PART` is `...3`

If they do not match, fix the variables before formatting. The block
below assumes you created the partitions in the order above. If you
created them in a different order, do not use it; read the actual
numbers from `lsblk` and set each variable by hand.

```bash
case "$ARCH_DISK" in
  *nvme*|*mmcblk*) SEP=p ;;
  *)               SEP= ;;
esac
export EFI_PART="${ARCH_DISK}${SEP}1"
export ROOT_PART="${ARCH_DISK}${SEP}2"
if [ -n "$SWAP_PART" ]; then
  export SWAP_PART="${ARCH_DISK}${SEP}2"
  export ROOT_PART="${ARCH_DISK}${SEP}3"
fi
```

Formatting is the next step.

Press `q`, then run `harch format`.
