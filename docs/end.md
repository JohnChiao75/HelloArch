# Step 10 · Finish

Everything is installed. If your prompt is inside the new system,
leave the chroot:

```bash
exit
```

If you are already at the live ISO prompt, skip that command.

Unmount and reboot:

```bash
cd /
umount -R /mnt
swapoff -a
reboot
```

Remove the ISO when the firmware asks.

## After the reboot

Log in as the user you created. Then:

```bash
sudo nmtui
sudo pacman -Syu
```

`nmtui` opens a text menu for Wi-Fi. If you use Ethernet, it is
usually already connected.

If something went wrong, boot the ISO again, re-export the disk
variables from step 2, mount the system, and `arch-chroot /mnt` to
fix it.

You are done.
