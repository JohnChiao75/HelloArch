#!/usr/bin/env bash
# helloarch - Automated Arch Linux Installation Script
# Version: 1.0.0
# License: MIT
# Description: Implementation following the helloarch development document

set -o pipefail  # Fail pipeline if any command fails, but do not use set -e for fine-grained control

##############################
# Global Configuration & Constants
##############################
SCRIPT_NAME="helloarch"
LOG_FILE="/tmp/helloarch.log"
PACMAN_CONF="/etc/pacman.conf"
MIRRORLIST="/etc/pacman.d/mirrorlist"
MOUNT_POINT="/mnt"
# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

##############################
# Utility Functions
##############################

# Log informational messages (printed to terminal and log file)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

# Log success messages
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

# Log error messages
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

# Log warning messages
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

# Pause and wait for user to press Enter
pause() {
    read -rp "Press Enter to continue..." </dev/tty
}

# Confirm an action (y/n), default can be specified as second argument ("y" or "n")
confirm() {
    local prompt="$1 (y/N) "
    local default="n"
    if [[ "$2" == "y" ]]; then
        prompt="$1 (Y/n) "
        default="y"
    fi
    local ans
    while true; do
        read -rp "$prompt" ans </dev/tty
        ans=${ans:-$default}
        case "$ans" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

# Terminate with error message and exit
die() {
    log_error "$*"
    log_error "Installation failed. Check log at $LOG_FILE"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root."
    fi
}

# Check network connectivity (ping archlinux.org)
check_network() {
    log_info "Checking network connectivity..."
    if ping -c 3 archlinux.org &>/dev/null; then
        log_success "Network is up."
        return 0
    else
        log_error "Network unreachable. Please check your network settings."
        return 1
    fi
}

# Safely execute a command; on failure, ask to retry or exit
safe_run() {
    local cmd="$*"
    log_info "Executing: $cmd"
    if eval "$cmd"; then
        return 0
    else
        log_error "Command failed: $cmd"
        if confirm "Retry?" "y"; then
            safe_run "$cmd"
        else
            die "User chose to exit."
        fi
    fi
}

##############################
# Module 1: Configure Mirrors
##############################
configure_mirrors() {
    log_info "Starting mirror configuration..."

    # Backup existing mirrorlist if present
    if [[ -f "$MIRRORLIST" ]]; then
        cp "$MIRRORLIST" "$MIRRORLIST.bak"
    fi

    # Ask user for mirror configuration method
    echo "Select mirror configuration method:"
    echo "1) Auto-generate with reflector (requires reflector installed)"
    echo "2) Manually edit /etc/pacman.d/mirrorlist"
    echo "3) Skip, keep current mirrorlist"
    local choice
    read -rp "Enter number [1-3]: " choice </dev/tty

    case "$choice" in
        1)
            if command -v reflector &>/dev/null; then
                log_info "Generating mirror list with reflector..."
                if safe_run "reflector --country China --age 12 --protocol https --sort rate --save $MIRRORLIST"; then
                    log_success "Mirror list updated."
                else
                    log_warn "Reflector failed, switching to manual edit."
                    nano "$MIRRORLIST"
                fi
            else
                log_warn "Reflector not installed, will edit manually."
                nano "$MIRRORLIST"
            fi
            ;;
        2)
            nano "$MIRRORLIST"
            ;;
        3)
            log_info "Skipping mirror configuration."
            ;;
        *)
            log_warn "Invalid choice, skipping."
            ;;
    esac

    # Test latency of selected mirror
    log_info "Testing mirror latency..."
    local fastest=$(head -n 1 "$MIRRORLIST" | grep -o 'Server = .*' | sed 's/Server = //' | sed 's/$repo\/os\/$arch//' | head -1)
    if [[ -n "$fastest" ]]; then
        log_info "Testing $fastest ..."
        if ping -c 2 "${fastest#http://}" &>/dev/null || ping -c 2 "${fastest#https://}" &>/dev/null; then
            log_success "Mirror is reachable."
        else
            log_warn "Selected mirror may be unreachable, please check."
        fi
    else
        log_warn "Could not parse mirror URL."
    fi

    # Update pacman cache
    safe_run "pacman -Sy"
    log_success "Mirror configuration completed."
}

##############################
# Module 2: Disk Partitioning
##############################
# Global variables to store partition info
ROOT_PART=""
BOOT_PART=""
SWAP_PART=""
HOME_PART=""
FS_TYPE=""          # btrfs, ext4, exfat
USE_BTRFS=false
PARTITION_SCHEME="" # auto, manual, existing

partition_disk() {
    log_info "Starting disk partitioning..."

    # List available disks
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
    echo

    # Select target disk
    local disk
    while true; do
        read -rp "Enter target disk device (e.g., /dev/sda): " disk </dev/tty
        if [[ -b "$disk" ]]; then
            break
        else
            log_error "Device $disk does not exist or is not a block device. Please re-enter."
        fi
    done

    # Warn about data loss
    log_warn "All data on $disk will be destroyed!"
    if ! confirm "Are you sure you want to continue?" "n"; then
        die "User cancelled partitioning."
    fi

    # Select partitioning scheme
    echo "Select partitioning scheme:"
    echo "1) Auto-recommended (UEFI+GPT: EFI partition, swap, root partition)"
    echo "2) Manual partitioning (using cfdisk)"
    echo "3) Use existing partitions (skip creation, go directly to formatting)"
    local scheme_choice
    read -rp "Enter number [1-3]: " scheme_choice </dev/tty

    case "$scheme_choice" in
        1)
            PARTITION_SCHEME="auto"
            log_info "Auto-partitioning: GPT table, EFI (512MiB), swap (size = RAM), root (remaining)"
            local mem_total=$(free -m | awk '/^Mem:/{print $2}')
            local swap_size=$((mem_total))
            log_info "Memory: ${mem_total}MiB, swap size: ${swap_size}MiB"

            # Check if disk is mounted (prevent mistakes)
            if mount | grep -q "$disk"; then
                log_warn "Disk $disk has mounted partitions. Continuing may damage your system."
                if ! confirm "Continue anyway?" "n"; then
                    die "User cancelled partitioning."
                fi
            fi

            # Clear partition table (write zeros to first 512 bytes)
            dd if=/dev/zero of="$disk" bs=512 count=1 &>/dev/null

            # Create partitions with parted
            safe_run "parted -s $disk mklabel gpt"
            safe_run "parted -s $disk mkpart primary fat32 1MiB 513MiB"
            safe_run "parted -s $disk set 1 esp on"
            safe_run "parted -s $disk mkpart primary linux-swap 513MiB $((513 + swap_size))MiB"
            safe_run "parted -s $disk mkpart primary ext4 $((513 + swap_size))MiB 100%"

            BOOT_PART="${disk}1"
            SWAP_PART="${disk}2"
            ROOT_PART="${disk}3"
            HOME_PART=""  # No separate /home partition; will use Btrfs subvolumes if chosen
            log_info "Partitions created:"
            lsblk "$disk"
            ;;
        2)
            PARTITION_SCHEME="manual"
            log_info "Opening cfdisk for manual partitioning. Please follow these guidelines:"
            echo "  - Use GPT partition table (recommended)"
            echo "  - Create an EFI system partition (type EFI System, at least 512MiB)"
            echo "  - Create a swap partition (type Linux swap, optional)"
            echo "  - Create a root partition (type Linux filesystem)"
            echo "  - Optionally create a separate /home partition"
            pause
            cfdisk "$disk"
            if ! confirm "Have you finished partitioning?" "y"; then
                die "User did not complete partitioning."
            fi
            lsblk "$disk"
            echo "Enter the partition devices according to the list above:"
            read -rp "EFI partition (e.g., ${disk}1): " BOOT_PART </dev/tty
            read -rp "Swap partition (e.g., ${disk}2, leave empty if none): " SWAP_PART </dev/tty
            read -rp "Root partition (e.g., ${disk}3): " ROOT_PART </dev/tty
            read -rp "Home partition (e.g., ${disk}4, leave empty if none): " HOME_PART </dev/tty
            if [[ -z "$ROOT_PART" ]]; then
                die "Root partition must be specified."
            fi
            ;;
        3)
            PARTITION_SCHEME="existing"
            log_info "Using existing partitions. Skipping creation, proceeding to formatting."
            lsblk "$disk"
            echo "Enter existing partition devices:"
            read -rp "EFI partition (e.g., ${disk}1): " BOOT_PART </dev/tty
            read -rp "Swap partition (e.g., ${disk}2, leave empty if none): " SWAP_PART </dev/tty
            read -rp "Root partition (e.g., ${disk}3): " ROOT_PART </dev/tty
            read -rp "Home partition (e.g., ${disk}4, leave empty if none): " HOME_PART </dev/tty
            if [[ -z "$ROOT_PART" ]]; then
                die "Root partition must be specified."
            fi
            ;;
        *)
            die "Invalid choice."
            ;;
    esac

    # Verify partition devices exist
    for part in "$BOOT_PART" "$SWAP_PART" "$ROOT_PART" "$HOME_PART"; do
        if [[ -n "$part" ]] && [[ ! -b "$part" ]]; then
            die "Partition $part does not exist."
        fi
    done

    log_success "Partition selection completed."
}

##############################
# Module 3: Formatting & Subvolumes
##############################
format_partitions() {
    log_info "Starting partition formatting..."

    # Ask for root filesystem type
    echo "Select root filesystem type:"
    echo "1) Btrfs (recommended, supports subvolumes)"
    echo "2) ext4"
    echo "3) exfat (not recommended for root)"
    local fs_choice
    read -rp "Enter number [1-3]: " fs_choice </dev/tty
    case "$fs_choice" in
        1)
            FS_TYPE="btrfs"
            USE_BTRFS=true
            ;;
        2)
            FS_TYPE="ext4"
            ;;
        3)
            FS_TYPE="exfat"
            ;;
        *)
            log_warn "Invalid choice, defaulting to ext4."
            FS_TYPE="ext4"
            ;;
    esac

    # Confirm formatting
    log_warn "The following partitions will be formatted:"
    [[ -n "$BOOT_PART" ]] && echo "  EFI: $BOOT_PART (FAT32)"
    [[ -n "$SWAP_PART" ]] && echo "  Swap: $SWAP_PART"
    echo "  Root: $ROOT_PART ($FS_TYPE)"
    [[ -n "$HOME_PART" ]] && echo "  Home: $HOME_PART ($FS_TYPE)"
    if ! confirm "Are you sure you want to proceed with formatting?" "n"; then
        die "User cancelled formatting."
    fi

    # Format EFI partition (FAT32)
    if [[ -n "$BOOT_PART" ]]; then
        log_info "Formatting EFI partition $BOOT_PART ..."
        safe_run "mkfs.fat -F32 $BOOT_PART"
    else
        log_warn "No EFI partition specified, skipping formatting."
    fi

    # Format swap partition
    if [[ -n "$SWAP_PART" ]]; then
        log_info "Formatting swap partition $SWAP_PART ..."
        safe_run "mkswap $SWAP_PART"
    fi

    # Format root partition
    log_info "Formatting root partition $ROOT_PART as $FS_TYPE ..."
    case "$FS_TYPE" in
        btrfs)
            safe_run "mkfs.btrfs -f $ROOT_PART"
            ;;
        ext4)
            safe_run "mkfs.ext4 -F $ROOT_PART"
            ;;
        exfat)
            safe_run "mkfs.exfat $ROOT_PART"
            ;;
        *)
            die "Unsupported filesystem: $FS_TYPE"
            ;;
    esac

    # If a separate home partition exists, format it (same FS as root)
    if [[ -n "$HOME_PART" ]]; then
        log_info "Formatting home partition $HOME_PART as $FS_TYPE ..."
        case "$FS_TYPE" in
            btrfs)
                safe_run "mkfs.btrfs -f $HOME_PART"
                ;;
            ext4)
                safe_run "mkfs.ext4 -F $HOME_PART"
                ;;
            exfat)
                safe_run "mkfs.exfat $HOME_PART"
                ;;
        esac
    fi

    # If using Btrfs, create subvolumes @ and @home on the root partition
    if $USE_BTRFS; then
        log_info "Creating Btrfs subvolumes @ and @home ..."
        local temp_mount="/mnt/temp_btrfs"
        mkdir -p "$temp_mount"
        mount "$ROOT_PART" "$temp_mount" || die "Failed to mount root partition temporarily."
        btrfs subvolume create "$temp_mount/@"
        btrfs subvolume create "$temp_mount/@home"
        # If a separate /home partition exists, we ignore @home, but keep it just in case
        umount "$temp_mount"
        rmdir "$temp_mount"
        log_success "Btrfs subvolumes created."
    fi

    log_success "Formatting completed."
}

##############################
# Module 4: Mounting
##############################
mount_system() {
    log_info "Mounting partitions..."

    # Mount root partition
    if $USE_BTRFS; then
        mount -o subvol=@ "$ROOT_PART" "$MOUNT_POINT" || die "Failed to mount root subvolume @."
        mkdir -p "$MOUNT_POINT/home"
        mount -o subvol=@home "$ROOT_PART" "$MOUNT_POINT/home" || die "Failed to mount home subvolume @home."
    else
        mount "$ROOT_PART" "$MOUNT_POINT" || die "Failed to mount root partition."
        if [[ -n "$HOME_PART" ]]; then
            mkdir -p "$MOUNT_POINT/home"
            mount "$HOME_PART" "$MOUNT_POINT/home" || die "Failed to mount home partition."
        fi
    fi

    # Mount EFI partition
    if [[ -n "$BOOT_PART" ]]; then
        mkdir -p "$MOUNT_POINT/boot"
        mount "$BOOT_PART" "$MOUNT_POINT/boot" || die "Failed to mount EFI partition."
    else
        log_warn "EFI partition not mounted; system may not boot."
    fi

    # Enable swap
    if [[ -n "$SWAP_PART" ]]; then
        swapon "$SWAP_PART" || die "Failed to enable swap."
    fi

    # Generate fstab
    log_info "Generating fstab ..."
    genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab" || die "Failed to generate fstab."
    log_success "Mounting completed, fstab generated."
}

##############################
# Module 5: Install Base System
##############################
install_base() {
    log_info "Installing base system..."

    local packages="base base-devel linux linux-firmware sudo networkmanager neovim"
    log_info "Installing packages: $packages"
    safe_run "pacstrap -K $MOUNT_POINT $packages"  # -K initialises keyring

    log_success "Base system installed."
}

##############################
# Module 6: System Configuration (inside chroot)
##############################
configure_system() {
    log_info "Configuring system..."

    # Prepare chroot configuration script
    cat > "$MOUNT_POINT/root/configure_chroot.sh" << 'EOF'
#!/bin/bash
set -e

# Timezone
echo "Enter timezone (e.g., Asia/Shanghai):"
read -rp "Timezone: " timezone </dev/tty
if [[ -n "$timezone" ]]; then
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    hwclock --systohc
fi

# Locale
echo "Enter locale (e.g., en_US.UTF-8):"
read -rp "Locale: " locale </dev/tty
locale=${locale:-en_US.UTF-8}
echo "$locale UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf

# Hostname
read -rp "Enter hostname: " hostname </dev/tty
if [[ -n "$hostname" ]]; then
    echo "$hostname" > /etc/hostname
fi

# Set root password
echo "Set root password:"
passwd

# Create ordinary user
read -rp "Enter username for ordinary user (default: arch): " username </dev/tty
username=${username:-arch}
useradd -m -G wheel -s /bin/bash "$username"
echo "Set password for user $username:"
passwd "$username"

# Configure sudo: allow wheel group to run all commands
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Enable NetworkManager
systemctl enable NetworkManager

# Optional pacman configuration
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

EOF

    chmod +x "$MOUNT_POINT/root/configure_chroot.sh"
    log_info "Running configuration script inside chroot..."
    arch-chroot "$MOUNT_POINT" /root/configure_chroot.sh || die "System configuration failed."

    # Cleanup
    rm -f "$MOUNT_POINT/root/configure_chroot.sh"

    log_success "System configuration completed."
}

##############################
# Module 7: Install archlinuxcn repo and yay
##############################
install_aur_helper() {
    log_info "Installing archlinuxcn repository and yay..."

    cat > "$MOUNT_POINT/root/install_aur.sh" << 'EOF'
#!/bin/bash
set -e

# Add archlinuxcn repository to pacman.conf
echo "Adding archlinuxcn repository..."
if ! grep -q '^\[archlinuxcn\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf << EOL

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
EOL
fi

# Install archlinuxcn-keyring
pacman -Sy --noconfirm archlinuxcn-keyring

# Install yay
if pacman -Qi yay &>/dev/null; then
    echo "yay already installed."
else
    echo "Installing yay ..."
    pacman -S --noconfirm yay
fi

# If yay installation failed, try building from AUR
if ! command -v yay &>/dev/null; then
    echo "Building yay from AUR ..."
    pacman -S --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
fi

EOF

    chmod +x "$MOUNT_POINT/root/install_aur.sh"
    log_info "Installing archlinuxcn and yay ..."
    arch-chroot "$MOUNT_POINT" /root/install_aur.sh || die "Failed to install AUR helper."
    rm -f "$MOUNT_POINT/root/install_aur.sh"

    log_success "archlinuxcn and yay installed."
}

##############################
# Module 8: Install Desktop Environment
##############################
install_desktop() {
    log_info "Installing desktop environment..."

    echo "Select a desktop environment to install:"
    echo "1) Plasma (KDE)"
    echo "2) GNOME"
    echo "3) Hyprland (Wayland tiling window manager)"
    echo "4) Niri (scrollable Wayland compositor)"
    echo "5) No desktop (command-line only)"
    local de_choice
    read -rp "Enter number [1-5]: " de_choice </dev/tty

    local de_packages=""
    local display_manager=""
    case "$de_choice" in
        1)
            de_packages="plasma-meta konsole dolphin sddm"
            display_manager="sddm"
            ;;
        2)
            de_packages="gnome gdm"
            display_manager="gdm"
            ;;
        3)
            de_packages="hyprland polkit-kde-agent waybar wofi foot fuzzel"
            display_manager=""  # Hyprland usually uses seatd or manual start
            ;;
        4)
            de_packages="niri foot fuzzel"
            display_manager=""  # Niri similar
            ;;
        5)
            log_info "Skipping desktop installation."
            return
            ;;
        *)
            log_warn "Invalid choice, skipping desktop installation."
            return
            ;;
    esac

    if [[ -n "$de_packages" ]]; then
        log_info "Installing desktop packages: $de_packages"
        arch-chroot "$MOUNT_POINT" pacman -S --noconfirm $de_packages || die "Failed to install desktop packages."
    fi

    # Enable display manager
    if [[ -n "$display_manager" ]]; then
        log_info "Enabling $display_manager ..."
        arch-chroot "$MOUNT_POINT" systemctl enable "$display_manager" || log_warn "Failed to enable $display_manager."
    else
        # For Hyprland and Niri, enable seatd and give instructions
        if [[ "$de_choice" == "3" || "$de_choice" == "4" ]]; then
            arch-chroot "$MOUNT_POINT" systemctl enable seatd || log_warn "Failed to enable seatd."
            log_info "Desktop environment installed."
            echo "Note: Hyprland/Niri require manual start after login (add 'exec Hyprland' to .zshrc or .bashrc)."
            echo "Alternatively, you can use a display manager like SDDM to launch Hyprland."
        fi
    fi

    # Install basic graphics drivers (simple detection)
    log_info "Installing basic graphics drivers..."
    arch-chroot "$MOUNT_POINT" pacman -S --noconfirm mesa xf86-video-vesa &>/dev/null || log_warn "Graphics driver installation failed."

    log_success "Desktop environment installation completed."
}

##############################
# Main Function
##############################
main() {
    # Initialize log
    > "$LOG_FILE"
    log_info "========== $SCRIPT_NAME started =========="

    # Check root
    check_root

    # Check network
    if ! check_network; then
        if ! confirm "Network is down. Continue anyway?" "n"; then
            die "Network connectivity is required."
        fi
    fi

    # Show welcome
    echo -e "${GREEN}Welcome to $SCRIPT_NAME - Arch Linux automated installer!${NC}"
    echo "This script will guide you through the installation. Please read prompts carefully."
    echo "WARNING: All data on the target disk will be destroyed! Ensure you have backups."
    pause

    # Execute modules
    configure_mirrors
    partition_disk
    format_partitions
    mount_system
    install_base
    configure_system
    install_aur_helper
    install_desktop

    # Finish
    log_success "Installation complete!"
    echo "Reboot your system with the following commands:"
    echo "  umount -R $MOUNT_POINT"
    echo "  reboot"
    echo "Remember to remove the installation media before rebooting."
    log_info "Log saved to $LOG_FILE"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
