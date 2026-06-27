#!/usr/bin/env bash
# helloarch - 自动化 Arch Linux 安装脚本
# 版本: 1.0.0
# 许可证: MIT
# 描述: 按照 helloarch 开发文档实现的自动化安装脚本

set -o pipefail  # 管道命令中任一命令失败则整体失败，但不禁用 set -e，以便细粒度错误处理

##############################
# 全局配置与常量
##############################
SCRIPT_NAME="helloarch"
LOG_FILE="/tmp/helloarch.log"
PACMAN_CONF="/etc/pacman.conf"
MIRRORLIST="/etc/pacman.d/mirrorlist"
MOUNT_POINT="/mnt"
# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

##############################
# 工具函数
##############################

# 记录信息日志 (同时输出到终端和日志文件)
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

# 记录成功日志
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

# 记录错误日志
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

# 记录警告日志
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

# 显示提示并等待用户按 Enter 继续
pause() {
    read -rp "按 Enter 继续..." </dev/tty
}

# 确认操作 (y/n)，默认值可通过第二个参数指定 (y 或 n)
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
            *) echo "请输入 y 或 n。" ;;
        esac
    done
}

# 错误终止函数，显示错误信息并退出
die() {
    log_error "$*"
    log_error "安装失败，请检查日志 $LOG_FILE"
    exit 1
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "此脚本必须以 root 用户运行。"
    fi
}

# 检查网络连通性 (ping archlinux.org)
check_network() {
    log_info "检查网络连通性..."
    if ping -c 3 archlinux.org &>/dev/null; then
        log_success "网络连通正常。"
        return 0
    else
        log_error "网络连接失败，请检查网络设置。"
        return 1
    fi
}

# 安全执行命令，失败时提示并询问是否重试或退出
safe_run() {
    local cmd="$*"
    log_info "执行: $cmd"
    if eval "$cmd"; then
        return 0
    else
        log_error "命令执行失败: $cmd"
        if confirm "是否重试？" "y"; then
            safe_run "$cmd"
        else
            die "用户选择退出。"
        fi
    fi
}

##############################
# 模块1: 配置镜像源
##############################
configure_mirrors() {
    log_info "开始配置镜像源..."

    # 如果已经存在 mirrorlist，备份
    if [[ -f "$MIRRORLIST" ]]; then
        cp "$MIRRORLIST" "$MIRRORLIST.bak"
    fi

    # 询问用户编辑方式
    echo "请选择镜像源配置方式:"
    echo "1) 自动使用 reflector 生成最新镜像列表 (需安装 reflector)"
    echo "2) 手动编辑 /etc/pacman.d/mirrorlist"
    echo "3) 跳过，使用当前镜像列表"
    local choice
    read -rp "输入数字 [1-3]: " choice </dev/tty

    case "$choice" in
        1)
            if command -v reflector &>/dev/null; then
                log_info "使用 reflector 生成镜像列表..."
                if safe_run "reflector --country China --age 12 --protocol https --sort rate --save $MIRRORLIST"; then
                    log_success "镜像列表已更新。"
                else
                    log_warn "reflector 失败，将跳转到手动编辑。"
                    nano "$MIRRORLIST"
                fi
            else
                log_warn "未安装 reflector，将手动编辑。"
                nano "$MIRRORLIST"
            fi
            ;;
        2)
            nano "$MIRRORLIST"
            ;;
        3)
            log_info "跳过镜像源配置。"
            ;;
        *)
            log_warn "无效选择，跳过。"
            ;;
    esac

    # 测试选中的镜像源延迟
    log_info "测试镜像源延迟..."
    local fastest=$(head -n 1 "$MIRRORLIST" | grep -o 'Server = .*' | sed 's/Server = //' | sed 's/$repo\/os\/$arch//' | head -1)
    if [[ -n "$fastest" ]]; then
        log_info "测试 $fastest ..."
        if ping -c 2 "${fastest#http://}" &>/dev/null || ping -c 2 "${fastest#https://}" &>/dev/null; then
            log_success "镜像源可访问。"
        else
            log_warn "选中的镜像源可能不可访问，请检查。"
        fi
    else
        log_warn "无法解析镜像源地址。"
    fi

    # 更新 pacman 缓存
    safe_run "pacman -Sy"
    log_success "镜像源配置完成。"
}

##############################
# 模块2: 磁盘分区
##############################
# 全局变量存储分区信息
ROOT_PART=""
BOOT_PART=""
SWAP_PART=""
HOME_PART=""
FS_TYPE=""          # btrfs, ext4, exfat
USE_BTRFS=false
PARTITION_SCHEME="" # auto, manual, existing

partition_disk() {
    log_info "开始磁盘分区..."

    # 列出所有可用磁盘
    echo "可用磁盘列表:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "loop"
    echo

    # 选择目标磁盘
    local disk
    while true; do
        read -rp "请输入目标磁盘设备 (如 /dev/sda): " disk </dev/tty
        if [[ -b "$disk" ]]; then
            break
        else
            log_error "设备 $disk 不存在或不是块设备，请重新输入。"
        fi
    done

    # 警告数据丢失
    log_warn "磁盘 $disk 上的所有数据将被破坏！"
    if ! confirm "你确定要继续吗？" "n"; then
        die "用户取消分区操作。"
    fi

    # 选择分区方案
    echo "请选择分区方案:"
    echo "1) 自动推荐 (UEFI + GPT + EFI分区 + 交换分区 + 根分区)"
    echo "2) 手动分区 (使用 cfdisk)"
    echo "3) 使用现有分区 (跳过创建，直接进入格式化)"
    local scheme_choice
    read -rp "输入数字 [1-3]: " scheme_choice </dev/tty

    case "$scheme_choice" in
        1)
            PARTITION_SCHEME="auto"
            # 自动分区: 使用 parted
            log_info "自动分区方案: 创建 GPT 分区表，EFI 分区 (512MiB)，交换分区 (与内存等大)，根分区 (剩余空间)"
            # 获取内存大小 (MiB)
            local mem_total=$(free -m | awk '/^Mem:/{print $2}')
            local swap_size=$((mem_total))
            log_info "内存大小: ${mem_total}MiB，交换分区大小: ${swap_size}MiB"

            # 检查磁盘是否已被挂载 (防止误操作)
            if mount | grep -q "$disk"; then
                log_warn "磁盘 $disk 上存在挂载点，继续操作可能导致系统损坏。"
                if ! confirm "是否继续？" "n"; then
                    die "用户取消分区。"
                fi
            fi

            # 清除磁盘分区表 (使用 dd 清零前512字节确保干净)
            dd if=/dev/zero of="$disk" bs=512 count=1 &>/dev/null

            # 使用 parted 创建分区
            safe_run "parted -s $disk mklabel gpt"
            # 创建 EFI 分区 (类型为 EFI System)
            safe_run "parted -s $disk mkpart primary fat32 1MiB 513MiB"
            safe_run "parted -s $disk set 1 esp on"
            # 创建交换分区
            safe_run "parted -s $disk mkpart primary linux-swap 513MiB $((513 + swap_size))MiB"
            # 创建根分区 (剩余空间)
            safe_run "parted -s $disk mkpart primary ext4 $((513 + swap_size))MiB 100%"

            # 设置全局变量
            BOOT_PART="${disk}1"
            SWAP_PART="${disk}2"
            ROOT_PART="${disk}3"
            HOME_PART=""  # 不单独划分 home 分区，将在 Btrfs 子卷中处理
            log_info "分区创建成功:"
            lsblk "$disk"
            ;;
        2)
            PARTITION_SCHEME="manual"
            log_info "将打开 cfdisk 进行手动分区。请按以下指导操作:"
            echo "  - 建议使用 GPT 分区表"
            echo "  - 创建 EFI 分区 (类型 EFI System, 至少 512MiB)"
            echo "  - 创建交换分区 (类型 Linux swap, 可选)"
            echo "  - 创建根分区 (类型 Linux filesystem)"
            echo "  - 如有需要可创建单独 /home 分区"
            pause
            # 运行 cfdisk
            cfdisk "$disk"
            # 让用户确认分区完成
            if ! confirm "分区完成了吗？" "y"; then
                die "用户未完成分区。"
            fi
            # 列出分区供用户选择
            lsblk "$disk"
            echo "请根据上面列表输入各分区设备路径:"
            read -rp "EFI 分区 (如 ${disk}1): " BOOT_PART </dev/tty
            read -rp "交换分区 (如 ${disk}2, 没有则留空): " SWAP_PART </dev/tty
            read -rp "根分区 (如 ${disk}3): " ROOT_PART </dev/tty
            read -rp "Home 分区 (如 ${disk}4, 没有则留空): " HOME_PART </dev/tty
            if [[ -z "$ROOT_PART" ]]; then
                die "根分区必须指定。"
            fi
            ;;
        3)
            PARTITION_SCHEME="existing"
            log_info "使用现有分区，将跳过创建，直接进入格式化。"
            lsblk "$disk"
            echo "请输入现有分区设备路径:"
            read -rp "EFI 分区 (如 ${disk}1): " BOOT_PART </dev/tty
            read -rp "交换分区 (如 ${disk}2, 没有则留空): " SWAP_PART </dev/tty
            read -rp "根分区 (如 ${disk}3): " ROOT_PART </dev/tty
            read -rp "Home 分区 (如 ${disk}4, 没有则留空): " HOME_PART </dev/tty
            if [[ -z "$ROOT_PART" ]]; then
                die "根分区必须指定。"
            fi
            ;;
        *)
            die "无效选择。"
            ;;
    esac

    # 验证分区设备存在
    for part in "$BOOT_PART" "$SWAP_PART" "$ROOT_PART" "$HOME_PART"; do
        if [[ -n "$part" ]] && [[ ! -b "$part" ]]; then
            die "分区 $part 不存在。"
        fi
    done

    log_success "分区确定完成。"
}

##############################
# 模块3: 格式化与子卷
##############################
format_partitions() {
    log_info "开始格式化分区..."

    # 询问根分区文件系统类型
    echo "请选择根分区文件系统:"
    echo "1) Btrfs (推荐，支持子卷)"
    echo "2) ext4"
    echo "3) exfat (不推荐用于根分区)"
    local fs_choice
    read -rp "输入数字 [1-3]: " fs_choice </dev/tty
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
            log_warn "无效选择，默认使用 ext4。"
            FS_TYPE="ext4"
            ;;
    esac

    # 确认格式化操作
    log_warn "即将格式化以下分区:"
    [[ -n "$BOOT_PART" ]] && echo "  EFI: $BOOT_PART (FAT32)"
    [[ -n "$SWAP_PART" ]] && echo "  交换: $SWAP_PART"
    echo "  根: $ROOT_PART ($FS_TYPE)"
    [[ -n "$HOME_PART" ]] && echo "  Home: $HOME_PART ($FS_TYPE)"
    if ! confirm "确定要继续格式化吗？" "n"; then
        die "用户取消格式化。"
    fi

    # 格式化 EFI 分区 (FAT32)
    if [[ -n "$BOOT_PART" ]]; then
        log_info "格式化 EFI 分区 $BOOT_PART ..."
        safe_run "mkfs.fat -F32 $BOOT_PART"
    else
        log_warn "未指定 EFI 分区，跳过格式化。"
    fi

    # 格式化交换分区
    if [[ -n "$SWAP_PART" ]]; then
        log_info "格式化交换分区 $SWAP_PART ..."
        safe_run "mkswap $SWAP_PART"
    fi

    # 格式化根分区
    log_info "格式化根分区 $ROOT_PART 为 $FS_TYPE ..."
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
            die "不支持的文件系统: $FS_TYPE"
            ;;
    esac

    # 如果存在 home 分区，格式化 (与根分区相同文件系统)
    if [[ -n "$HOME_PART" ]]; then
        log_info "格式化 Home 分区 $HOME_PART 为 $FS_TYPE ..."
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

    # 如果使用 Btrfs，创建子卷 @ 和 @home (在根分区上)
    if $USE_BTRFS; then
        log_info "为 Btrfs 创建子卷 @ 和 @home ..."
        # 先挂载根分区到临时目录
        local temp_mount="/mnt/temp_btrfs"
        mkdir -p "$temp_mount"
        mount "$ROOT_PART" "$temp_mount" || die "无法挂载根分区到临时目录。"
        # 创建子卷
        btrfs subvolume create "$temp_mount/@"
        btrfs subvolume create "$temp_mount/@home"
        # 若存在 home 分区，我们使用单独分区而不是子卷，所以忽略 @home 但保留
        # 卸载
        umount "$temp_mount"
        rmdir "$temp_mount"
        log_success "Btrfs 子卷创建完成。"
    fi

    log_success "格式化完成。"
}

##############################
# 模块4: 挂载
##############################
mount_system() {
    log_info "开始挂载分区..."

    # 挂载根分区
    if $USE_BTRFS; then
        # 挂载子卷 @ 到 /mnt
        mount -o subvol=@ "$ROOT_PART" "$MOUNT_POINT" || die "无法挂载根子卷 @。"
        # 创建 home 目录并挂载 @home 子卷
        mkdir -p "$MOUNT_POINT/home"
        mount -o subvol=@home "$ROOT_PART" "$MOUNT_POINT/home" || die "无法挂载 home 子卷 @home。"
    else
        # 直接挂载根分区
        mount "$ROOT_PART" "$MOUNT_POINT" || die "无法挂载根分区。"
        # 如果有独立 home 分区，挂载
        if [[ -n "$HOME_PART" ]]; then
            mkdir -p "$MOUNT_POINT/home"
            mount "$HOME_PART" "$MOUNT_POINT/home" || die "无法挂载 home 分区。"
        fi
    fi

    # 挂载 EFI 分区
    if [[ -n "$BOOT_PART" ]]; then
        mkdir -p "$MOUNT_POINT/boot"
        mount "$BOOT_PART" "$MOUNT_POINT/boot" || die "无法挂载 EFI 分区。"
    else
        log_warn "未挂载 EFI 分区，可能无法启动。"
    fi

    # 启用交换分区
    if [[ -n "$SWAP_PART" ]]; then
        swapon "$SWAP_PART" || die "无法启用交换分区。"
    fi

    # 生成 fstab
    log_info "生成 fstab ..."
    genfstab -U "$MOUNT_POINT" >> "$MOUNT_POINT/etc/fstab" || die "生成 fstab 失败。"
    log_success "挂载完成，fstab 已生成。"
}

##############################
# 模块5: 安装基础系统
##############################
install_base() {
    log_info "开始安装基础系统..."

    # 安装 base, base-devel, linux, linux-firmware, sudo, networkmanager 等
    local packages="base base-devel linux linux-firmware sudo networkmanager neovim"
    log_info "安装包: $packages"
    safe_run "pacstrap -K $MOUNT_POINT $packages"  # -K 表示 keyring 初始化

    log_success "基础系统安装完成。"
}

##############################
# 模块6: 系统配置 (在 chroot 中执行)
##############################
configure_system() {
    log_info "开始系统配置..."

    # 准备 chroot 脚本
    cat > "$MOUNT_POINT/root/configure_chroot.sh" << 'EOF'
#!/bin/bash
set -e

# 时区
echo "请输入时区 (如 Asia/Shanghai):"
read -rp "时区: " timezone </dev/tty
if [[ -n "$timezone" ]]; then
    ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
    hwclock --systohc
fi

# locale
echo "请输入 locale (如 en_US.UTF-8):"
read -rp "locale: " locale </dev/tty
locale=${locale:-en_US.UTF-8}
echo "$locale UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$locale" > /etc/locale.conf

# 主机名
read -rp "请输入主机名: " hostname </dev/tty
if [[ -n "$hostname" ]]; then
    echo "$hostname" > /etc/hostname
fi

# 设置 root 密码
echo "设置 root 密码:"
passwd

# 创建普通用户
read -rp "请输入普通用户名 (默认 arch): " username </dev/tty
username=${username:-arch}
useradd -m -G wheel -s /bin/bash "$username"
echo "设置用户 $username 密码:"
passwd "$username"

# 配置 sudo: 允许 wheel 组执行所有命令
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# 启用 NetworkManager
systemctl enable NetworkManager

# 配置 pacman (可选)
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

EOF

    chmod +x "$MOUNT_POINT/root/configure_chroot.sh"
    log_info "在 chroot 环境中执行配置脚本..."
    arch-chroot "$MOUNT_POINT" /root/configure_chroot.sh || die "系统配置失败。"

    # 清理配置脚本
    rm -f "$MOUNT_POINT/root/configure_chroot.sh"

    log_success "系统配置完成。"
}

##############################
# 模块7: 安装 archlinuxcn 源和 yay
##############################
install_aur_helper() {
    log_info "开始安装 archlinuxcn 源和 yay..."

    # 在 chroot 中执行安装
    cat > "$MOUNT_POINT/root/install_aur.sh" << 'EOF'
#!/bin/bash
set -e

# 添加 archlinuxcn 仓库到 pacman.conf
echo "添加 archlinuxcn 仓库..."
if ! grep -q '^\[archlinuxcn\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf << EOL

[archlinuxcn]
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch
EOL
fi

# 安装 archlinuxcn-keyring
pacman -Sy --noconfirm archlinuxcn-keyring

# 安装 yay
if pacman -Qi yay &>/dev/null; then
    echo "yay 已安装。"
else
    echo "安装 yay ..."
    pacman -S --noconfirm yay
fi

# 如果 yay 安装失败，尝试从 AUR 构建
if ! command -v yay &>/dev/null; then
    echo "从 AUR 构建 yay ..."
    pacman -S --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
fi

EOF

    chmod +x "$MOUNT_POINT/root/install_aur.sh"
    log_info "安装 archlinuxcn 和 yay ..."
    arch-chroot "$MOUNT_POINT" /root/install_aur.sh || die "安装 AUR 助手失败。"
    rm -f "$MOUNT_POINT/root/install_aur.sh"

    log_success "archlinuxcn 源和 yay 安装完成。"
}

##############################
# 模块8: 安装桌面环境
##############################
install_desktop() {
    log_info "开始安装桌面环境..."

    echo "请选择要安装的桌面环境:"
    echo "1) Plasma (KDE)"
    echo "2) GNOME"
    echo "3) Hyprland (Wayland 平铺窗口管理器)"
    echo "4) Niri (滚动式 Wayland 合成器)"
    echo "5) 不安装桌面 (仅命令行)"
    local de_choice
    read -rp "输入数字 [1-5]: " de_choice </dev/tty

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
            display_manager=""  # Hyprland 通常使用 seatd 或手动启动
            ;;
        4)
            de_packages="niri foot fuzzel"
            display_manager=""  # Niri 类似
            ;;
        5)
            log_info "跳过桌面安装。"
            return
            ;;
        *)
            log_warn "无效选择，跳过桌面安装。"
            return
            ;;
    esac

    if [[ -n "$de_packages" ]]; then
        log_info "安装桌面包: $de_packages"
        # 在 chroot 中安装
        arch-chroot "$MOUNT_POINT" pacman -S --noconfirm $de_packages || die "安装桌面包失败。"
    fi

    # 启用显示管理器
    if [[ -n "$display_manager" ]]; then
        log_info "启用 $display_manager ..."
        arch-chroot "$MOUNT_POINT" systemctl enable "$display_manager" || log_warn "启用 $display_manager 失败。"
    else
        # 对于 Hyprland 和 Niri，启用 seatd 并提示
        if [[ "$de_choice" == "3" || "$de_choice" == "4" ]]; then
            arch-chroot "$MOUNT_POINT" systemctl enable seatd || log_warn "启用 seatd 失败。"
            log_info "桌面环境安装完成。"
            echo "注意: Hyprland/Niri 需要用户登录后手动启动 (可在 .zshrc 或 .bashrc 中添加 exec Hyprland 等)。"
            echo "或者使用显示管理器如 SDDM 也可以启动 Hyprland。"
        fi
    fi

    # 安装图形驱动 (简单检测)
    log_info "安装基本图形驱动..."
    # 检测虚拟机或常见显卡，简单安装 mesa 和 xf86-video-vesa
    arch-chroot "$MOUNT_POINT" pacman -S --noconfirm mesa xf86-video-vesa &>/dev/null || log_warn "图形驱动安装失败。"

    # 如果检测到 NVIDIA 或 Intel，可额外安装，但此处简化

    log_success "桌面环境安装完成。"
}

##############################
# 主函数
##############################
main() {
    # 初始化日志
    > "$LOG_FILE"
    log_info "========== $SCRIPT_NAME 启动 =========="

    # 检查 root
    check_root

    # 检查网络
    if ! check_network; then
        if ! confirm "网络不通，是否继续？" "n"; then
            die "网络必须正常。"
        fi
    fi

    # 显示欢迎信息
    echo -e "${GREEN}欢迎使用 $SCRIPT_NAME Arch Linux 自动化安装脚本！${NC}"
    echo "本脚本将引导您完成安装过程。请仔细阅读提示。"
    echo "警告: 磁盘数据将被破坏！请确保已备份重要数据。"
    pause

    # 执行各个模块
    configure_mirrors
    partition_disk
    format_partitions
    mount_system
    install_base
    configure_system
    install_aur_helper
    install_desktop

    # 完成
    log_success "安装完成！"
    echo "请执行以下命令重启系统:"
    echo "  umount -R $MOUNT_POINT"
    echo "  reboot"
    echo "注意: 重启前请移除安装介质。"
    log_info "日志保存在 $LOG_FILE"
}

# 执行主函数 (如果脚本直接运行)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
