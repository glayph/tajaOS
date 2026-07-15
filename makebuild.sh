#!/bin/bash
# ============================================================
#  NEXUS OS — Slim Build Script (Target: ~500MB ISO)
#  Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]
# ============================================================
set -e

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[NEXUS]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
warn() { echo -e "${Y}[ WARN]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

CLEAN=false; NO_SQUASH=false; OUTPUT_DIR="$(pwd)"
for arg in "$@"; do
  case $arg in
    --clean)     CLEAN=true ;;
    --no-squash) NO_SQUASH=true ;;
    --output)    OUTPUT_DIR="$2"; shift ;;
    --help)      echo "Usage: sudo ./makebuild.sh [--clean] [--no-squash] [--output DIR]"; exit 0 ;;
  esac
done

[[ $EUID -ne 0 ]] && die "Run as root: sudo ./makebuild.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS="$SCRIPT_DIR/rootfs"
ISO_DIR="$SCRIPT_DIR/iso"
OUTPUT_ISO="$OUTPUT_DIR/nexus.iso"

log "Nexus OS Slim Build — Target: ~500MB ISO"
log "Output: $OUTPUT_ISO"

# ── Step 1: Clean ──────────────────────────────────────────
if $CLEAN; then
  warn "Removing existing rootfs..."
  rm -rf "$ROOTFS" "$ISO_DIR" core.img bios.img efiboot.img
fi

# ── Step 2: Bootstrap ─────────────────────────────────────
if [[ ! -d "$ROOTFS/bin" ]]; then
  log "Bootstrapping Ubuntu 24.04 Noble (minbase)..."
  debootstrap --arch=amd64 --variant=minbase noble "$ROOTFS" \
    http://archive.ubuntu.com/ubuntu/ 2>&1 | grep -E "^[EW]:" || true
  ok "Bootstrap done"
else
  warn "Rootfs exists — skipping (use --clean to rebuild)"
fi

# ── Step 3: apt sources ───────────────────────────────────
cat > "$ROOTFS/etc/apt/sources.list" << 'SOURCES'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe
deb http://security.ubuntu.com/ubuntu noble-security main restricted universe
SOURCES

# ── Step 4: Mount ─────────────────────────────────────────
mountpoint -q "$ROOTFS/proc" || mount --bind /proc "$ROOTFS/proc"
mountpoint -q "$ROOTFS/sys"  || mount --bind /sys  "$ROOTFS/sys"
mountpoint -q "$ROOTFS/dev"  || mount --bind /dev  "$ROOTFS/dev"
trap "umount '$ROOTFS/proc' '$ROOTFS/sys' '$ROOTFS/dev' 2>/dev/null; true" EXIT

# ── Step 5: Install packages — SLIM selection ──────────────
log "Installing slim package set..."
chroot "$ROOTFS" /bin/bash -c "
  apt-get update -qq

  # Size reduction 1: linux-image-virtual (no extra hardware modules)
  # Instead of linux-image-generic (600MB) → linux-image-virtual (~200MB)
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-image-virtual \
    initramfs-tools \
    live-boot \
    live-boot-initramfs-tools \
    python3 \
    python3-requests \
    bash \
    coreutils \
    systemd \
    systemd-sysv \
    util-linux \
    procps \
    iproute2 \
    iputils-ping \
    nano \
    curl \
    ca-certificates \
    2>&1 | grep -E '^(Setting up|E:)' | head -30

  echo root:nexus | chpasswd

  # Size reduction 2: Remove ALL unnecessary files after install
  echo '[NEXUS] Cleaning up to reduce size...'

  # Remove apt cache (biggest win: ~200MB)
  apt-get clean
  apt-get autoremove -y --purge 2>/dev/null || true
  rm -rf /var/lib/apt/lists/*
  rm -rf /var/cache/apt/archives/*.deb
  rm -rf /var/cache/apt/archives/partial/

  # Remove kernel build artifacts (not needed in live ISO)
  rm -rf /usr/src/linux-headers-*
  rm -rf /usr/share/doc/*
  rm -rf /usr/share/man/*
  rm -rf /usr/share/locale/*
  rm -rf /usr/share/info/*
  rm -rf /var/log/*.log /var/log/*.gz

  # Remove unused kernel modules (saves 200-400MB)
  KVER=\$(ls /boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')
  echo \"Removing unused kernel modules for \$KVER...\"

  # Keep only essential modules, remove huge driver collections
  cd /lib/modules/\$KVER/kernel
  rm -rf drivers/media      2>/dev/null || true
  rm -rf drivers/staging    2>/dev/null || true
  rm -rf drivers/gpu/drm    2>/dev/null || true
  rm -rf drivers/bluetooth  2>/dev/null || true
  rm -rf drivers/infiniband 2>/dev/null || true
  rm -rf drivers/isdn       2>/dev/null || true
  rm -rf drivers/atm        2>/dev/null || true
  rm -rf drivers/nfc        2>/dev/null || true
  rm -rf drivers/iio        2>/dev/null || true
  rm -rf sound              2>/dev/null || true
  cd /

  # Rebuild module deps after removal
  depmod -a \$KVER 2>/dev/null || true

  echo '[NEXUS] Cleanup done.'
"

ok "Package install and cleanup done"

# ── Step 6: Custom packages ────────────────────────────────
if [[ -f "$SCRIPT_DIR/customize/packages.list" ]]; then
  PKGS=$(grep -v '^\s*#' "$SCRIPT_DIR/customize/packages.list" | grep -v '^\s*$' | tr '\n' ' ')
  if [[ -n "$PKGS" ]]; then
    log "Installing custom packages: $PKGS"
    mountpoint -q "$ROOTFS/proc" || mount --bind /proc "$ROOTFS/proc"
    mountpoint -q "$ROOTFS/sys"  || mount --bind /sys  "$ROOTFS/sys"
    mountpoint -q "$ROOTFS/dev"  || mount --bind /dev  "$ROOTFS/dev"
    chroot "$ROOTFS" /bin/bash -c "
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $PKGS \
        2>&1 | grep -E '^(Setting up|E:)' || true
      apt-get clean && rm -rf /var/lib/apt/lists/*
    "
  fi
fi

# ── Step 7: Nexus AI Agent ────────────────────────────────
log "Installing Nexus AI Agent..."
mkdir -p "$ROOTFS/etc/nexus"
cp "$SCRIPT_DIR/nexus-agent.py" "$ROOTFS/usr/local/bin/nexus-agent.py"
chmod +x "$ROOTFS/usr/local/bin/nexus-agent.py"

cat > "$ROOTFS/usr/local/bin/nexus" << 'LAUNCHER'
#!/bin/bash
export TERM=linux
export PYTHONUNBUFFERED=1
[ -f /etc/nexus/api.key ] && export ANTHROPIC_API_KEY=$(cat /etc/nexus/api.key)
exec /usr/local/bin/nexus-agent.py
LAUNCHER
chmod +x "$ROOTFS/usr/local/bin/nexus"

# ── Step 8: System identity ───────────────────────────────
log "Configuring system identity..."
echo "nexus" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'HOSTS'
127.0.0.1   localhost
127.0.1.1   nexus
::1         localhost ip6-localhost ip6-loopback
HOSTS

cat > "$ROOTFS/etc/os-release" << OSREL
NAME="Nexus OS"
VERSION="1.0"
ID=nexus
ID_LIKE=ubuntu
PRETTY_NAME="Nexus OS 1.0 — Agentic AI Linux"
NEXUS_AGENT="claude-sonnet-4-6"
BUILD_DATE=$(date +%Y-%m-%d)
OSREL

# Auto-login
mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
GETTY

cat > "$ROOTFS/root/.bash_profile" << 'PROFILE'
if [ "$(tty)" = "/dev/tty1" ]; then
  exec /usr/local/bin/nexus
fi
PROFILE

# Custom files
[[ -f "$SCRIPT_DIR/customize/startup.sh" ]] && \
  cp "$SCRIPT_DIR/customize/startup.sh" "$ROOTFS/etc/nexus/startup.sh" && \
  chmod +x "$ROOTFS/etc/nexus/startup.sh"

[[ -f "$SCRIPT_DIR/customize/motd.txt" ]] && \
  cp "$SCRIPT_DIR/customize/motd.txt" "$ROOTFS/etc/motd" || \
  cat > "$ROOTFS/etc/motd" << 'MOTD'

  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗  ██████╗ ███████╗
  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗ ██║   ██║███████╗
  ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║ ╚██████╔╝███████║

  Nexus OS 1.0 — Agentic AI Linux  |  'nexus' to launch AI agent

MOTD

# ── Step 9: Rebuild initramfs ─────────────────────────────
log "Rebuilding initramfs with live-boot..."
chroot "$ROOTFS" update-initramfs -u -k all 2>&1 | tail -3

umount "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev" 2>/dev/null || true
trap - EXIT

# ── Step 10: ISO structure ────────────────────────────────
log "Building ISO structure..."
mkdir -p "$ISO_DIR/boot/grub" "$ISO_DIR/EFI/boot" "$ISO_DIR/live"

KVER=$(ls "$ROOTFS/boot/vmlinuz-"* 2>/dev/null | sort -V | tail -1 | sed 's/.*vmlinuz-//')
[[ -z "$KVER" ]] && die "No kernel found in $ROOTFS/boot/"
log "Kernel: $KVER"

cp "$ROOTFS/boot/vmlinuz-${KVER}"    "$ISO_DIR/boot/vmlinuz"
cp "$ROOTFS/boot/initrd.img-${KVER}" "$ISO_DIR/boot/initrd.img"
cp "$SCRIPT_DIR/boot/grub/grub.cfg"  "$ISO_DIR/boot/grub/grub.cfg"

# ── Step 11: Squashfs — Size reduction 3: XZ compression ──
if ! $NO_SQUASH; then
  log "Creating squashfs with XZ compression (better ratio, slower)..."
  mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz \
    -Xbcj x86 \
    -b 1M \
    -e boot \
    -noappend \
    2>&1 | tail -3
  ok "Squashfs: $(du -sh $ISO_DIR/live/filesystem.squashfs | cut -f1)"
else
  warn "Skipping squashfs (--no-squash)"
fi

# ── Step 12: GRUB bootloaders ────────────────────────────
log "Building GRUB bootloaders..."

grub-mkstandalone \
  --format=x86_64-efi \
  --output="$ISO_DIR/EFI/boot/bootx64.efi" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

grub-mkstandalone \
  --format=i386-pc \
  --output="$SCRIPT_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk search" \
  --locales="" --fonts="" \
  "boot/grub/grub.cfg=$ISO_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$SCRIPT_DIR/core.img" > "$SCRIPT_DIR/bios.img"

dd if=/dev/zero of="$SCRIPT_DIR/efiboot.img" bs=1M count=4 status=none
mkfs.fat -F12 "$SCRIPT_DIR/efiboot.img"
mmd   -i "$SCRIPT_DIR/efiboot.img" ::/EFI ::/EFI/boot
mcopy -i "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/EFI/boot/bootx64.efi" ::/EFI/boot/

cp "$SCRIPT_DIR/bios.img"    "$ISO_DIR/bios.img"
cp "$SCRIPT_DIR/efiboot.img" "$ISO_DIR/efiboot.img"
ok "Bootloaders ready"

# ── Step 13: Build ISO ───────────────────────────────────
log "Building nexus.iso..."
xorriso -as mkisofs \
  -iso-level 3 \
  -volid "NEXUS_OS_1_0" \
  -appid "Nexus OS 1.0 Agentic AI Linux" \
  -publisher "Nexus AI Project" \
  -b bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
  -eltorito-alt-boot \
  -e efiboot.img \
    -no-emul-boot \
  --protective-msdos-label \
  -append_partition 2 0xef "$SCRIPT_DIR/efiboot.img" \
  -o "$OUTPUT_ISO" \
  "$ISO_DIR"

# ── Done ─────────────────────────────────────────────────
echo ""
ok "BUILD COMPLETE!"
echo ""
echo "  ISO    : $OUTPUT_ISO"
echo "  Size   : $(du -sh $OUTPUT_ISO | cut -f1)"
echo "  SHA256 : $(sha256sum $OUTPUT_ISO | cut -d' ' -f1)"
echo ""
echo "  Flash  : dd if=nexus.iso of=/dev/sdX bs=4M status=progress"
echo "  VM     : make qemu"
