#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"

usage() {
  cat <<USAGE
Usage: $(basename "$0")

Build a rootfs from the Armada OS container image for the Y700.

Extracts the Armada bootc container into a plain ext4 rootfs, strips
bootc/ostree internals, applies Y700 device overlay and sensor/haptics/camera
.deb packages, then boots via the existing GRUB chain (no initramfs).

Environment inputs:
  OUTPUT_DIR                 default: out/ci-rootfs
  OUTPUT_PREFIX              default: armada-y700
  ARMADA_IMAGE               Armada container image (default: ghcr.io/armada-os/armada:testing)
  ROOTFS_IMAGE_SIZE          default: 24G
  ROOTFS_UUID                optional ext4 UUID
  ROOTFS_LABEL               default: Armada
  ROOTFS_PARTLABEL           default: userdata
  HOSTNAME_NAME              default: y700
  DEFAULT_USER_NAME          default: armada
  DEFAULT_USER_PASSWORD      default: deck
  SENSOR_DEB_DIR             directory containing sensor .deb files
  HAPTICS_DEB_DIR            directory containing haptics .deb files
  CAMERA_STACK_DEB_DIR       directory containing camera stack .deb files
  BUILD_TB321FU_GPU_SENSOR   build/install TB321FU GPU sensor plugin, default: 1
  TB321FU_GPU_SENSOR_SOURCE_DIR
                              optional source directory for the plugin
  TB321FU_GPU_SENSOR_BUILD_JOBS
                              parallel build jobs, default: 2
  APPLY_Y700_FIRMWARE_FIXES  copy/verify required Y700 firmware paths, default: 1
  APPLY_Y700_AUDIO_POLICY_FIXES
                              install Y700 WirePlumber ALSA policy, default: 1
  COMPRESS                   none|zstd|xz|7z, default: 7z
  CHUNK_SIZE                 optional 7z volume size
  KEEP_RAW_IMAGE             keep uncompressed rootfs image after packaging, default: 0
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

ci_require_cmd mkfs.ext4
ci_require_cmd mount
ci_require_cmd umount
ci_require_cmd e2fsck
ci_require_cmd rsync
ci_require_cmd sha256sum

OUTPUT_DIR=${OUTPUT_DIR:-out/ci-rootfs}
OUTPUT_PREFIX=${OUTPUT_PREFIX:-armada-y700}
ARMADA_IMAGE=${ARMADA_IMAGE:-ghcr.io/armada-os/armada:testing}
ROOTFS_IMAGE_SIZE=${ROOTFS_IMAGE_SIZE:-24G}
ROOTFS_LABEL=${ROOTFS_LABEL:-Armada}
ROOTFS_PARTLABEL=${ROOTFS_PARTLABEL:-userdata}
HOSTNAME_NAME=${HOSTNAME_NAME:-y700}
DEFAULT_USER_NAME=${DEFAULT_USER_NAME:-armada}
DEFAULT_USER_PASSWORD=${DEFAULT_USER_PASSWORD:-deck}
SENSOR_DEB_DIR=${SENSOR_DEB_DIR:-}
HAPTICS_DEB_DIR=${HAPTICS_DEB_DIR:-}
CAMERA_STACK_DEB_DIR=${CAMERA_STACK_DEB_DIR:-}
BUILD_TB321FU_GPU_SENSOR=${BUILD_TB321FU_GPU_SENSOR:-1}
TB321FU_GPU_SENSOR_SOURCE_DIR=${TB321FU_GPU_SENSOR_SOURCE_DIR:-}
TB321FU_GPU_SENSOR_BUILD_JOBS=${TB321FU_GPU_SENSOR_BUILD_JOBS:-2}
APPLY_Y700_FIRMWARE_FIXES=${APPLY_Y700_FIRMWARE_FIXES:-1}
APPLY_Y700_AUDIO_POLICY_FIXES=${APPLY_Y700_AUDIO_POLICY_FIXES:-1}
COMPRESS=${COMPRESS:-7z}
CHUNK_SIZE=${CHUNK_SIZE:-}
KEEP_RAW_IMAGE=${KEEP_RAW_IMAGE:-0}

mkdir -p "$OUTPUT_DIR"
work_dir=$(mktemp -d "$OUTPUT_DIR/.armada-rootfs.XXXXXX")
rootfs_dir="$work_dir/rootfs"
rootfs_img="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.img"
mounted=0

cleanup() {
  set +e
  if [ "$mounted" = 1 ]; then
    for p in dev/pts dev proc sys run; do
      mountpoint -q "$rootfs_dir/$p" && umount -l "$rootfs_dir/$p"
    done
    mountpoint -q "$rootfs_dir" && umount "$rootfs_dir"
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

# ── Phase 1: Extract Armada container image ─────────────────────────────

# Use crane to export container filesystem — no daemon, no storage driver conflicts
if ! command -v crane &>/dev/null; then
  ci_log "installing crane"
  crane_url="https://github.com/google/go-containerregistry/releases/download/v0.20.3/go-containerregistry_Linux_arm64.tar.gz"
  curl -fL --retry 3 -o /tmp/crane.tar.gz "$crane_url"
  tar -C /tmp -xzf /tmp/crane.tar.gz crane
  sudo install -m 0755 /tmp/crane /usr/local/bin/crane
  rm -f /tmp/crane /tmp/crane.tar.gz
fi

ci_log "creating ext4 image: $rootfs_img"
rm -f "$rootfs_img"
truncate -s "$ROOTFS_IMAGE_SIZE" "$rootfs_img"
mkfs_args=(-F -L "$ROOTFS_LABEL")
if [ -n "${ROOTFS_UUID:-}" ]; then
  mkfs_args+=(-U "$ROOTFS_UUID")
fi
mkfs.ext4 "${mkfs_args[@]}" "$rootfs_img"

mkdir -p "$rootfs_dir"
mount -o loop "$rootfs_img" "$rootfs_dir"
mounted=1

ci_log "exporting container filesystem: $ARMADA_IMAGE"
crane export "$ARMADA_IMAGE" - | tar -C "$rootfs_dir" -xf -

# ── Phase 2: Strip bootc/ostree internals ──────────────────────────────

ci_log "stripping bootc/ostree internals"

# Remove ostree directories
rm -rf \
  "$rootfs_dir/sysroot" \
  "$rootfs_dir/ostree" \
  "$rootfs_dir/var/lib/ostree" \
  "$rootfs_dir/var/lib/bootc"

# Mask bootc/ostree systemd services
ostree_units=(
  ostree-prepare-root.service
  ostree-remount.service
  bootc-install.service
  bootc-fetch-atomic-updates.service
  rpm-ostreed.service
  rpm-ostreed-automatic.timer
)
for unit in "${ostree_units[@]}"; do
  svc_path="$rootfs_dir/etc/systemd/system/$unit"
  mkdir -p "$(dirname "$svc_path")"
  ln -sf /dev/null "$svc_path"
done

# Disable SELinux (no policy for Y700)
if [ -f "$rootfs_dir/etc/selinux/config" ]; then
  sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' "$rootfs_dir/etc/selinux/config"
  sed -i 's/^SELINUX=permissive/SELINUX=disabled/' "$rootfs_dir/etc/selinux/config"
fi

# Remove ostree configuration
rm -rf "$rootfs_dir/etc/ostree"

# ── Phase 3: Y700 device overlay ───────────────────────────────────────

apply_y700_firmware_fixes() {
  local root=$1

  ci_log "applying Y700 firmware path fixes"

  install -d -m 0755 "$root/lib/firmware/qcom" "$root/lib/firmware/qcom/sm8650" "$root/lib/firmware/qcom/vpu"

  copy_firmware_if_missing() {
    local source_rel=$1
    local dest_rel=$2
    [ -f "$root/$source_rel" ] || return 1
    if [ -e "$root/$dest_rel" ]; then
      return 0
    fi
    install -d -m 0755 "$(dirname "$root/$dest_rel")"
    install -m 0644 "$root/$source_rel" "$root/$dest_rel"
  }

  local src dst
  for src in \
    usr/lib/firmware/qcom/sm8650/lenovo/tb321fu/gen70900_zap.mbn \
    lib/firmware/qcom/sm8650/lenovo/tb321fu/gen70900_zap.mbn; do
    if copy_firmware_if_missing "$src" lib/firmware/qcom/gen70900_zap.mbn; then
      break
    fi
  done
  for src in \
    usr/lib/firmware/qcom-tb321fu/Lenovo-Y700-TB321FU-tplg.bin \
    lib/firmware/qcom-tb321fu/Lenovo-Y700-TB321FU-tplg.bin; do
    if copy_firmware_if_missing "$src" lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin; then
      break
    fi
  done

  for src in \
    usr/lib/firmware/qcom/gen70900_aqe.fw \
    usr/lib/firmware/qcom/gen70900_sqe.fw \
    usr/lib/firmware/qcom/gmu_gen70900.bin \
    usr/lib/firmware/qcom/vpu/vpu33_p4.mbn; do
    dst=${src#usr/}
    copy_firmware_if_missing "$src" "$dst" || true
  done

  local required=(
    lib/firmware/qcom/gen70900_aqe.fw
    lib/firmware/qcom/gen70900_sqe.fw
    lib/firmware/qcom/gen70900_zap.mbn
    lib/firmware/qcom/gmu_gen70900.bin
    lib/firmware/qcom/sm8650/Lenovo-Y700-TB321FU-tplg.bin
    lib/firmware/qcom/vpu/vpu33_p4.mbn
  )
  local rel
  for rel in "${required[@]}"; do
    [ -e "$root/$rel" ] || [ -L "$root/$rel" ] || ci_die "missing Y700 required firmware: $rel"
  done
}

apply_y700_audio_policy_fixes() {
  local root=$1
  local conf_dir="$root/etc/wireplumber/wireplumber.conf.d"
  local conf="$conf_dir/51-y700-alsa-auto.conf"

  ci_log "installing Y700 WirePlumber ALSA policy fix"

  install -d -m 0755 "$conf_dir"
  cat > "$conf" <<'CONF'
monitor.alsa.rules = [
  {
    matches = [
      {
        device.name = "alsa_card.platform-sound"
      }
    ]
    actions = {
      update-props = {
        api.alsa.use-acp = true
        api.alsa.use-ucm = true
        api.acp.auto-profile = true
        api.acp.auto-port = true
        api.alsa.split-enable = false
      }
    }
  }
]
CONF
  chmod 0644 "$conf"
  chown 0:0 "$conf" 2>/dev/null || true
}

apply_tb321fu_legacy_cleanup() {
  local root=$1

  ci_log "removing legacy y700 sensor and haptics glue"
  rm -f \
    "$root/etc/systemd/system/iio-sensor-proxy.service.d/10-y700-ssc.conf" \
    "$root/etc/systemd/system/y700-sns-init.service" \
    "$root/etc/systemd/system/y700-aw86937-haptics.service" \
    "$root/etc/udev/rules.d/90-y700-haptics.rules" \
    "$root/usr/local/libexec/y700-iio-sensor-proxy" \
    "$root/usr/local/sbin/y700-aw86937-bind"
  rm -rf \
    "$root/usr/local/lib/y700-sns" \
    "$root/usr/local/share/y700-sns"

  if [ -d "$root/etc/systemd/system/multi-user.target.wants" ]; then
    rm -f \
      "$root/etc/systemd/system/multi-user.target.wants/y700-sns-init.service" \
      "$root/etc/systemd/system/multi-user.target.wants/y700-aw86937-haptics.service"
  fi

  if [ -f "$root/usr/lib/systemd/system/qcom-sns-init.service" ]; then
    install -d -m 0755 "$root/etc/systemd/system/multi-user.target.wants"
    ln -sfn /usr/lib/systemd/system/qcom-sns-init.service \
      "$root/etc/systemd/system/multi-user.target.wants/qcom-sns-init.service"
  fi
  if [ -f "$root/usr/lib/systemd/system/tb321fu-haptics.service" ]; then
    install -d -m 0755 "$root/etc/systemd/system/multi-user.target.wants"
    ln -sfn /usr/lib/systemd/system/tb321fu-haptics.service \
      "$root/etc/systemd/system/multi-user.target.wants/tb321fu-haptics.service"
  fi

  if [ -x "$root/usr/libexec/iio-sensor-proxy" ]; then
    install -d -m 0755 "$root/usr/share/dbus-1/system-services"
    cat > "$root/usr/share/dbus-1/system-services/net.hadess.SensorProxy.service" <<'DBUS_SERVICE'
[D-BUS Service]
Name=net.hadess.SensorProxy
Exec=/usr/libexec/iio-sensor-proxy
User=root
SystemdService=iio-sensor-proxy.service
DBUS_SERVICE
    chmod 0644 "$root/usr/share/dbus-1/system-services/net.hadess.SensorProxy.service"
  fi
}

ci_log "applying Y700 device overlay"

# Overlay the armada-gaming-overlay (device config, session scripts)
overlay_dir="${SCRIPT_DIR}/../../source/armada-gaming-overlay"
if [ -d "$overlay_dir" ]; then
  rsync -aH --numeric-ids "$overlay_dir"/ "$rootfs_dir"/
fi

# Ensure Y700 DTB is in supported-dtbs
dtb_name="sm8650-lenovo-tb321fu"
supported_dtbs="$rootfs_dir/usr/lib/armada/supported-dtbs"
if [ -f "$supported_dtbs" ]; then
  if ! grep -q "^${dtb_name}$" "$supported_dtbs"; then
    echo "$dtb_name" >> "$supported_dtbs"
  fi
fi

apply_tb321fu_legacy_cleanup "$rootfs_dir"

if ci_bool "$APPLY_Y700_FIRMWARE_FIXES"; then
  apply_y700_firmware_fixes "$rootfs_dir"
fi
if ci_bool "$APPLY_Y700_AUDIO_POLICY_FIXES"; then
  apply_y700_audio_policy_fixes "$rootfs_dir"
fi

# ── Phase 4: Install Y700 .deb packages ────────────────────────────────

install_deb_into_rootfs() {
  local deb=$1
  local root=$2
  local tmp="$work_dir/deb-extract"

  rm -rf "$tmp"
  mkdir -p "$tmp"

  ci_log "extracting $(basename "$deb")"
  ar x --output="$tmp" "$deb"

  # Find the data archive (could be data.tar.xz, data.tar.gz, data.tar.zst, etc)
  local data_archive=""
  for candidate in "$tmp"/data.tar.*; do
    if [ -f "$candidate" ]; then
      data_archive="$candidate"
      break
    fi
  done
  [ -n "$data_archive" ] || ci_die "no data archive found in $deb"

  tar -C "$root" -xf "$data_archive"
  rm -rf "$tmp"
}

install_deb_dir() {
  local deb_dir=$1
  local root=$2
  local label=$3

  [ -d "$deb_dir" ] || return 0
  local count=0
  while IFS= read -r -d '' deb; do
    install_deb_into_rootfs "$deb" "$root"
    count=$((count + 1))
  done < <(find "$deb_dir" -maxdepth 1 -type f -name '*.deb' -print0)

  ci_log "installed $count $label .deb packages"
}

if [ -n "$SENSOR_DEB_DIR" ]; then
  install_deb_dir "$SENSOR_DEB_DIR" "$rootfs_dir" "sensor"
fi
if [ -n "$HAPTICS_DEB_DIR" ]; then
  install_deb_dir "$HAPTICS_DEB_DIR" "$rootfs_dir" "haptics"
fi
if [ -n "$CAMERA_STACK_DEB_DIR" ]; then
  install_deb_dir "$CAMERA_STACK_DEB_DIR" "$rootfs_dir" "camera"
fi

# ── Phase 5: Build GPU sensor plugin in chroot ─────────────────────────

apply_tb321fu_gpu_sensor() {
  local root=$1
  local source_dir=${TB321FU_GPU_SENSOR_SOURCE_DIR:-"$SCRIPT_DIR/../../source/tb321fu-ksystemstats-adreno-freq"}

  ci_log "building TB321FU KSystemStats Adreno GPU frequency plugin"

  [ -f "$source_dir/CMakeLists.txt" ] || ci_die "missing TB321FU GPU sensor source: $source_dir/CMakeLists.txt"
  [ -f "$source_dir/tb321fu_gpu.cpp" ] || ci_die "missing TB321FU GPU sensor source: $source_dir/tb321fu_gpu.cpp"
  [ -f "$source_dir/metadata.json" ] || ci_die "missing TB321FU GPU sensor source: $source_dir/metadata.json"

  # Detect Fedora lib64 paths for Qt6
  local qt6_plugin_dir
  if [ -d "$root/usr/lib64/qt6/plugins/ksystemstats" ]; then
    qt6_plugin_dir="usr/lib64/qt6/plugins/ksystemstats"
  elif [ -d "$root/usr/lib/aarch64-linux-gnu/qt6/plugins/ksystemstats" ]; then
    qt6_plugin_dir="usr/lib/aarch64-linux-gnu/qt6/plugins/ksystemstats"
  else
    qt6_plugin_dir="usr/lib64/qt6/plugins/ksystemstats"
  fi

  local plugin_rel="$qt6_plugin_dir/ksystemstats_plugin_tb321fu_gpu.so"
  local stock_plugin_rel="$qt6_plugin_dir/ksystemstats_plugin_gpu.so"
  local disabled_stock_plugin_rel="$stock_plugin_rel.disabled-tb321fu-adreno"

  local rootfs_src=/tmp/tb321fu-ksystemstats-adreno-freq-src
  local rootfs_build=/tmp/tb321fu-ksystemstats-adreno-freq-build

  rm -rf "$root$rootfs_src" "$root$rootfs_build"
  install -d -m 0755 "$root$rootfs_src"
  rsync -a --delete "$source_dir"/ "$root$rootfs_src"/

  cat > "$root/root/ci-build-tb321fu-gpu-sensor.sh" <<GPU_SENSOR_BUILD
#!/usr/bin/env bash
set -euo pipefail

src=/tmp/tb321fu-ksystemstats-adreno-freq-src
build=/tmp/tb321fu-ksystemstats-adreno-freq-build
plugin_rel="$plugin_rel"
stock_rel="$stock_plugin_rel"
disabled_rel="$disabled_stock_plugin_rel"

# Install build dependencies (Fedora/dnf)
dnf install -y \
  cmake extra-cmake-modules gcc-c++ make \
  kf6-ksysguard-devel kf6-coreaddons-devel \
  libsensors-devel qt6-qtbase-devel 2>/dev/null || \
dnf install -y \
  cmake extra-cmake-modules gcc-c++ make \
  kf6-ksysguard-devel kf6-coreaddons-devel \
  libsensors-devel qt6-base-devel

cmake -S "\$src" -B "\$build" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=/usr
cmake --build "\$build" -j${TB321FU_GPU_SENSOR_BUILD_JOBS}
cmake --install "\$build"

test -f "/\$plugin_rel"
if [ -f "/\$stock_rel" ]; then
  rm -f "/\$disabled_rel"
  mv "/\$stock_rel" "/\$disabled_rel"
fi
test ! -e "/\$stock_rel"

install -d -m 0755 /usr/share/tb321fu-ksystemstats-gpu
sha256sum "/\$plugin_rel" > /usr/share/tb321fu-ksystemstats-gpu/ksystemstats_plugin_tb321fu_gpu.so.sha256

rm -rf "\$src" "\$build"

# Clean up build deps
dnf remove -y --noautoremove \
  cmake extra-cmake-modules gcc-c++ make \
  kf6-ksysguard-devel kf6-coreaddons-devel \
  libsensors-devel qt6-qtbase-devel \
  2>/dev/null || true
dnf clean all

test -f "/\$plugin_rel"
test ! -e "/\$stock_rel"
test ! -e "/\$src"
test ! -e "/\$build"
GPU_SENSOR_BUILD
  chmod +x "$root/root/ci-build-tb321fu-gpu-sensor.sh"

  # Set up resolv.conf for network in chroot
  local resolv_backup="$work_dir/gpu-sensor-resolv.original"
  local resolv_link="$work_dir/gpu-sensor-resolv.link"
  rm -f "$resolv_backup" "$resolv_link"
  if [ -L "$root/etc/resolv.conf" ]; then
    readlink "$root/etc/resolv.conf" > "$resolv_link"
  elif [ -e "$root/etc/resolv.conf" ]; then
    cp -a "$root/etc/resolv.conf" "$resolv_backup"
  fi
  rm -f "$root/etc/resolv.conf"
  if [ -f /run/systemd/resolve/resolv.conf ]; then
    cp /run/systemd/resolve/resolv.conf "$root/etc/resolv.conf"
  else
    cp /etc/resolv.conf "$root/etc/resolv.conf"
  fi
  if ! awk '
    /^[[:space:]]*nameserver[[:space:]]+/ {
      ns=$2
      if (ns !~ /^(127\.|::1$|0\.0\.0\.0$)/) good=1
    }
    END { exit good ? 0 : 1 }
  ' "$root/etc/resolv.conf"; then
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$root/etc/resolv.conf"
  fi

  mount --bind /dev "$root/dev"
  mount --bind /dev/pts "$root/dev/pts"
  mount -t proc proc "$root/proc"
  mount -t sysfs sysfs "$root/sys"
  mount -t tmpfs tmpfs "$root/run"

  chroot "$root" /bin/bash /root/ci-build-tb321fu-gpu-sensor.sh

  for p in dev/pts dev proc sys run; do
    mountpoint -q "$root/$p" && umount -l "$root/$p"
  done

  rm -f "$root/etc/resolv.conf"
  if [ -f "$resolv_link" ]; then
    ln -s "$(cat "$resolv_link")" "$root/etc/resolv.conf"
  elif [ -f "$resolv_backup" ]; then
    cp -a "$resolv_backup" "$root/etc/resolv.conf"
  else
    ln -s ../run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
  fi

  rm -f "$root/root/ci-build-tb321fu-gpu-sensor.sh"
  [ -f "$root/$plugin_rel" ] || ci_die "TB321FU GPU sensor plugin missing after build: /$plugin_rel"
  [ ! -e "$root/$stock_plugin_rel" ] || ci_die "stock KSystemStats GPU plugin still enabled: /$stock_plugin_rel"
  [ -f "$root/$disabled_stock_plugin_rel" ] || ci_die "disabled stock KSystemStats GPU plugin missing: /$disabled_stock_plugin_rel"
}

if ci_bool "$BUILD_TB321FU_GPU_SENSOR"; then
  apply_tb321fu_gpu_sensor "$rootfs_dir"
fi

# ── Phase 6: User/system config ────────────────────────────────────────

ci_log "configuring hostname"
printf '%s\n' "$HOSTNAME_NAME" > "$rootfs_dir/etc/hostname"
touch "$rootfs_dir/etc/hosts"
sed -i '/^127\.0\.1\.1\b/d' "$rootfs_dir/etc/hosts"
printf '127.0.1.1 %s\n' "$HOSTNAME_NAME" >> "$rootfs_dir/etc/hosts"

ci_log "creating default user: $DEFAULT_USER_NAME"
mount --bind /dev "$rootfs_dir/dev"
mount --bind /dev/pts "$rootfs_dir/dev/pts"
mount -t proc proc "$rootfs_dir/proc"
mount -t sysfs sysfs "$rootfs_dir/sys"
mount -t tmpfs tmpfs "$rootfs_dir/run"

chroot "$rootfs_dir" /bin/bash -c "
  if ! id -u '$DEFAULT_USER_NAME' >/dev/null 2>&1; then
    useradd -m -s /bin/bash '$DEFAULT_USER_NAME'
  fi
  printf '%s:%s\n' '$DEFAULT_USER_NAME' '$DEFAULT_USER_PASSWORD' | chpasswd
  usermod -aG wheel,video,render,input,audio,seat,gamemode '$DEFAULT_USER_NAME' 2>/dev/null || \
  usermod -aG wheel,video,render,input,audio '$DEFAULT_USER_NAME' 2>/dev/null || true
" || true

for p in dev/pts dev proc sys run; do
  mountpoint -q "$rootfs_dir/$p" && umount -l "$rootfs_dir/$p"
done

ci_log "setting default target to graphical"
chroot "$rootfs_dir" systemctl set-default graphical.target 2>/dev/null || true

ci_log "enabling verbose systemd logging"
# Add debug shell on tty1 for error visibility
debug_service="$rootfs_dir/etc/systemd/system/debug-shell.service"
if [ ! -f "$debug_service" ]; then
  cat > "$debug_service" <<'DEBUG_SERVICE'
[Unit]
Description=Debug Shell
After=systemd-user-sessions.service
After=getty@tty1.service

[Service]
Type=simple
ExecStart=/bin/bash --login
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1

[Install]
WantedBy=multi-user.target
DEBUG_SERVICE
  chmod 0644 "$debug_service"
fi
install -d -m 0755 "$rootfs_dir/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/debug-shell.service \
  "$rootfs_dir/etc/systemd/system/multi-user.target.wants/debug-shell.service" 2>/dev/null || true

# Set systemd log level to debug
mkdir -p "$rootfs_dir/etc/systemd/system.conf.d"
cat > "$rootfs_dir/etc/systemd/system.conf.d/10-debug-log.conf" <<'LOGCONF'
[Manager]
LogLevel=debug
LogTarget=journal+console
LOGCONF
chmod 0644 "$rootfs_dir/etc/systemd/system.conf.d/10-debug-log.conf"

ci_log "cleaning up"
rm -f \
  "$rootfs_dir/etc/machine-id.bak" \
  "$rootfs_dir/var/log/wtmp" \
  "$rootfs_dir/var/log/btmp" \
  "$rootfs_dir/var/log/lastlog"
touch "$rootfs_dir/etc/machine-id"

# ── Phase 7: Output ────────────────────────────────────────────────────

ci_log "writing build info"
cat > "$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.BUILD-INFO.txt" <<INFO
generated=$(date -u -Iseconds)
armada_image=$ARMADA_IMAGE
hostname=$HOSTNAME_NAME
default_user=$DEFAULT_USER_NAME
rootfs_label=$ROOTFS_LABEL
rootfs_image_size=$ROOTFS_IMAGE_SIZE
sensor_deb_dir=${SENSOR_DEB_DIR:-}
haptics_deb_dir=${HAPTICS_DEB_DIR:-}
camera_stack_deb_dir=${CAMERA_STACK_DEB_DIR:-}
build_tb321fu_gpu_sensor=$BUILD_TB321FU_GPU_SENSOR
apply_y700_firmware_fixes=$APPLY_Y700_FIRMWARE_FIXES
apply_y700_audio_policy_fixes=$APPLY_Y700_AUDIO_POLICY_FIXES
INFO

ci_log "unmounting and checking image"
umount "$rootfs_dir"
mounted=0
e2fsck -f -y "$rootfs_img"

ci_log "checksumming rootfs image"
raw_sha_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.raw.sha256"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img")" > "$(basename "$raw_sha_file")")

checksum_file="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.SHA256SUMS"
build_info="$OUTPUT_DIR/${OUTPUT_PREFIX}-rootfs.BUILD-INFO.txt"
rm -f "$checksum_file"
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$build_info")" "$(basename "$raw_sha_file")" > "$(basename "$checksum_file")")
(cd "$OUTPUT_DIR" && sha256sum "$(basename "$raw_sha_file")" >> "$(basename "$checksum_file")")

case "$COMPRESS" in
  none)
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img")" >> "$(basename "$checksum_file")")
    ;;
  zstd)
    ci_require_cmd zstd
    zstd -T0 -19 -f "$rootfs_img" -o "$rootfs_img.zst"
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img").zst" >> "$(basename "$checksum_file")")
    ;;
  xz)
    xz -T0 -k -f "$rootfs_img"
    (cd "$OUTPUT_DIR" && sha256sum "$(basename "$rootfs_img").xz" >> "$(basename "$checksum_file")")
    ;;
  7z)
    ci_require_cmd 7z
    sevenz_out="$rootfs_img.7z"
    rm -f "$sevenz_out" "$sevenz_out".*
    if [ -n "${CHUNK_SIZE:-}" ]; then
      7z a "$sevenz_out" "$rootfs_img" -t7z -m0=lzma2 -mx=9 -mmt=on "-v$CHUNK_SIZE" >/dev/null
      (cd "$OUTPUT_DIR" && sha256sum "$(basename "$sevenz_out")".* >> "$(basename "$checksum_file")")
    else
      7z a "$sevenz_out" "$rootfs_img" -t7z -m0=lzma2 -mx=9 -mmt=on >/dev/null
      (cd "$OUTPUT_DIR" && sha256sum "$(basename "$sevenz_out")" >> "$(basename "$checksum_file")")
    fi
    ;;
  *) ci_die "unsupported COMPRESS=$COMPRESS" ;;
esac

if [ "$COMPRESS" != none ] && [ "$KEEP_RAW_IMAGE" != 1 ]; then
  rm -f "$rootfs_img"
fi

ci_log "Armada rootfs build complete: $OUTPUT_DIR"
