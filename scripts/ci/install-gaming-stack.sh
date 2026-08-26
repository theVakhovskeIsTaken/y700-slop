#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
. "$SCRIPT_DIR/common.sh"

INSTALL_GAMING_STACK=${INSTALL_GAMING_STACK:-1}
STEAM_CLIENT_URL=${STEAM_CLIENT_URL:-}
STEAM_RUNTIME_URL=${STEAM_RUNTIME_URL:-}
FEX_EMU_VERSION=${FEX_EMU_VERSION:-}
FEX_ROOTFS_URL=${FEX_ROOTFS_URL:-https://rootfs.fex-emu.gg/ArchLinux/2026-08-11/ArchLinux.sqsh}
PROTON_URL=${PROTON_URL:-https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20260703-slr/proton-cachyos-11.0-20260703-slr-arm64.tar.xz}
GAMESCOPE_URL=${GAMESCOPE_URL:-}
GAMESCOPE_SESSION_URL=${GAMESCOPE_SESSION_URL:-https://github.com/OpenGamingCollective/gamescope-session-steam/archive/refs/heads/main.tar.gz}
MANGOHUD_URL=${MANGOHUD_URL:-}
DECKY_LOADER_URL=${DECKY_LOADER_URL:-}
INPUTPLUMBER_URL=${INPUTPLUMBER_URL:-}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<USAGE
Usage: $(basename "$0")

Install Armada gaming stack components into a rootfs.

Environment inputs:
  INSTALL_GAMING_STACK       install gaming stack, default: 1
  STEAM_CLIENT_URL           optional URL to prebuilt Steam ARM64 client
  STEAM_RUNTIME_URL          optional URL to SteamRT ARM64 runtime
  FEX_EMU_VERSION            optional FEX version to install
  FEX_ROOTFS_URL             FEX Arch Linux rootfs URL
  PROTON_URL                 CachyOS Proton ARM64 URL
  GAMESCOPE_URL              optional URL to prebuilt Gamescope
  GAMESCOPE_SESSION_URL      Gamescope session Steam URL
  MANGOHUD_URL               optional URL to prebuilt MangoHud
  DECKY_LOADER_URL           optional URL to Decky Loader
  INPUTPLUMBER_URL           optional URL to InputPlumber
USAGE
  exit 0
fi

if [ "$INSTALL_GAMING_STACK" != "1" ]; then
  ci_log "INSTALL_GAMING_STACK is not 1; skipping gaming stack installation"
  exit 0
fi

rootfs_dir="${ROOTFS_DIR:-}"
if [ -z "$rootfs_dir" ] || [ ! -d "$rootfs_dir" ]; then
  ci_die "ROOTFS_DIR must be set to a valid rootfs directory"
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

install_fex_emu() {
  ci_log "installing FEX-EMU"

  if [ -n "$FEX_EMU_VERSION" ]; then
    local fex_url="https://github.com/FEX-Emu/FEX/archive/refs/tags/${FEX_EMU_VERSION}.tar.gz"
    local fex_archive="$work_dir/fex-source.tar.gz"
    ci_log "downloading FEX source: $fex_url"
    ci_download "$fex_url" "$fex_archive"
    
    mkdir -p "$rootfs_dir/tmp/fex-build"
    tar -C "$rootfs_dir/tmp/fex-build" -xzf "$fex_archive"
    
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y cmake g++ git build-essential libfmt-dev libgtest-dev libpixman-1-dev libsdl2-dev libsdl2-image-dev libwayland-dev libxkbcommon-dev wayland-protocols libdrm-dev libdisplay-info-dev nasm cmake pkg-config || true
    
    local fex_dir=$(ls -d "$rootfs_dir/tmp/fex-build/FEX-"* | head -1)
    if [ -d "$fex_dir" ]; then
      chroot "$rootfs_dir" bash -c "cd /tmp/fex-build/$(basename $fex_dir) && mkdir -p build && cd build && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr && make -j$(nproc) && make install" || true
    fi
    rm -rf "$rootfs_dir/tmp/fex-build"
  else
    ci_log "FEX_EMU_VERSION not set; installing FEX from packages"
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y fex-emu fex-emu-thunks || true
  fi

  install -d -m 0755 "$rootfs_dir/usr/share/fex-emu/RootFS"
  local rootfs_archive="$work_dir/ArchLinux.sqsh"
  ci_log "downloading FEX Arch Linux rootfs"
  ci_download "$FEX_ROOTFS_URL" "$rootfs_archive"
  cp -a "$rootfs_archive" "$rootfs_dir/usr/share/fex-emu/RootFS/ArchLinux.sqsh"

  install -d -m 0755 "$rootfs_dir/usr/share/fex-emu"
  cat > "$rootfs_dir/usr/share/fex-emu/Config.json" <<'FEXCONFIG'
{
  "Config": {
    "RootFS": "/usr/share/fex-emu/RootFS/ArchLinux.sqsh",
    "TSOEnabled": "1",
    "X87ReducedPrecision": "1",
    "Multiblock": "0",
    "VectorTSOEnabled": "0",
    "MemcpySetTSOEnabled": "0",
    "HalfBarrierTSOEnabled": "1",
    "ThunkHostLibs": "/usr/lib/aarch64-linux-gnu/fex-emu/HostThunks",
    "ThunkGuestLibs": "/usr/share/fex-emu/GuestThunks"
  },
  "ThunksDB": {
    "Vulkan": 1,
    "GL": 1,
    "drm": 1,
    "WaylandClient": 1,
    "asound": 1
  }
}
FEXCONFIG
}

install_proton() {
  ci_log "installing CachyOS Proton ARM64"

  local proton_archive="$work_dir/proton.tar.xz"
  ci_download "$PROTON_URL" "$proton_archive"

  local proton_dir="$rootfs_dir/usr/share/steam/compatibilitytools.d/proton-cachyos-arm64"
  install -d -m 0755 "$proton_dir"
  tar -C "$proton_dir" -xJf "$proton_archive"

  local proton_script="$proton_dir/proton"
  if [ -f "$proton_script" ]; then
    sed -i '/require_tool_appid/d' "$proton_script" 2>/dev/null || true
  fi

  local toolmanifest="$proton_dir/toolmanifest.vdf"
  if [ -f "$toolmanifest" ]; then
    sed -i '/require_tool_appid/d' "$toolmanifest" 2>/dev/null || true
  fi

  local compatvdf="$proton_dir/compatibilitytool.vdf"
  if [ -f "$compatvdf" ]; then
    sed -i 's/"display_name".*/"display_name" "Proton CachyOS (ARM64)"/' "$compatvdf" 2>/dev/null || true
  fi
}

install_gamescope() {
  ci_log "installing Gamescope"

  if [ -n "$GAMESCOPE_URL" ]; then
    local gs_archive="$work_dir/gamescope.tar.xz"
    ci_download "$GAMESCOPE_URL" "$gs_archive"
    tar -C "$rootfs_dir" -xJf "$gs_archive"
  else
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y gamescope || true
  fi

  install -d -m 0755 "$rootfs_dir/usr/share/gamescope-session-plus/sessions.d"
  chmod +x "$rootfs_dir/usr/share/gamescope-session-plus/sessions.d/steam" 2>/dev/null || true
}

install_mangohud() {
  ci_log "installing MangoHud"

  if [ -n "$MANGOHUD_URL" ]; then
    local mh_archive="$work_dir/mangohud.tar.xz"
    ci_download "$MANGOHUD_URL" "$mh_archive"
    tar -C "$rootfs_dir" -xJf "$mh_archive"
  else
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y mangohud || true
  fi
}

install_decky_loader() {
  ci_log "installing Decky Loader"

  local decky_dir="$rootfs_dir/usr/share/decky-loader"
  install -d -m 0755 "$decky_dir"

  if [ -n "$DECKY_LOADER_URL" ]; then
    local decky_archive="$work_dir/decky-loader.tar.gz"
    ci_download "$DECKY_LOADER_URL" "$decky_archive"
    tar -C "$decky_dir" -xzf "$decky_archive"
  else
    ci_log "DECKY_LOADER_URL not set; skipping Decky Loader installation"
    return 0
  fi

  local plugin_loader="$decky_dir/PluginLoader"
  if [ -f "$plugin_loader" ]; then
    chmod +x "$plugin_loader"
  fi

  install -d -m 0755 "$rootfs_dir/etc/systemd/system"
  cat > "$rootfs_dir/etc/systemd/system/plugin_loader.service" <<'SERVICE'
[Unit]
Description=Decky Loader
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/share/decky-loader/PluginLoader
Restart=on-failure
RestartSec=5
Environment=HOMEBREW_FOLDER=/var/home/armada/homebrew

[Install]
WantedBy=multi-user.target
SERVICE
  chmod 0644 "$rootfs_dir/etc/systemd/system/plugin_loader.service"
}

install_steam() {
  ci_log "installing Steam ARM64 client"

  if [ -n "$STEAM_CLIENT_URL" ]; then
    local steam_archive="$work_dir/steam-client.tar.gz"
    ci_download "$STEAM_CLIENT_URL" "$steam_archive"
    install -d -m 0755 "$rootfs_dir/home/armada/.local/share/Steam"
    tar -C "$rootfs_dir/home/armada/.local/share/Steam" -xzf "$steam_archive"
  else
    ci_log "installing Steam from Valve's official repo"
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y steam || true
    
    if [ ! -d "$rootfs_dir/home/armada/.local/share/Steam" ]; then
      install -d -m 0755 "$rootfs_dir/home/armada/.local/share/Steam"
    fi
  fi

  if [ -n "$STEAM_RUNTIME_URL" ]; then
    local runtime_archive="$work_dir/steamrt.tar.xz"
    ci_download "$STEAM_RUNTIME_URL" "$runtime_archive"
    install -d -m 0755 "$rootfs_dir/home/armada/.local/share/Steam/steamrtarm64"
    tar -C "$rootfs_dir/home/armada/.local/share/Steam/steamrtarm64" -xJf "$runtime_archive"
  fi

  local steam_bin="$rootfs_dir/usr/bin/steam"
  if [ ! -f "$steam_bin" ]; then
    cat > "$steam_bin" <<'STEAM_BIN'
#!/usr/bin/env bash
exec /usr/libexec/armada/launch-steam --desktop "$@"
STEAM_BIN
    chmod +x "$steam_bin"
  fi
  
  chown -R 1000:1000 "$rootfs_dir/home/armada" 2>/dev/null || true
}

install_inputplumber() {
  ci_log "installing InputPlumber"

  if [ -n "$INPUTPLUMBER_URL" ]; then
    local ip_deb="$work_dir/inputplumber.deb"
    ci_download "$INPUTPLUMBER_URL" "$ip_deb"
    if [[ "$INPUTPLUMBER_URL" == *.deb ]]; then
      cp -a "$ip_deb" "$rootfs_dir/var/tmp/ci-debs/" 2>/dev/null || true
    else
      tar -C "$rootfs_dir" -xzf "$ip_deb" 2>/dev/null || tar -C "$rootfs_dir" -xJf "$ip_deb" 2>/dev/null || true
    fi
  else
    chroot "$rootfs_dir" apt-get update || true
    chroot "$rootfs_dir" apt-get install -y inputplumber || true
  fi
}

install_gaming_packages() {
  ci_log "installing gaming dependencies"

  chroot "$rootfs_dir" apt-get update
  chroot "$rootfs_dir" apt-get install -y \
    vulkan-loader \
    vulkan-tools \
    xwayland \
    openal-soft \
    erofs-utils \
    squashfs-tools \
    fuse3 \
    libfuse3-3 \
    gamemode \
    libgamemode0 \
    libgamemodeauto.so.0 \
    libopenal1 \
    libpulse0 \
    pipewire \
    pipewire-pulse \
    wireplumber \
    steam-devices || true
}

install_system_files() {
  ci_log "installing Armada system files"

  local overlay="${SCRIPT_DIR}/../../source/armada-gaming-overlay"
  if [ -d "$overlay" ]; then
    rsync -aH --numeric-ids "$overlay"/ "$rootfs_dir"/
  fi

  chmod +x "$rootfs_dir/usr/libexec/armada/device-env" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/libexec/armada/launch-steam" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/libexec/armada/armada-game-launch" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/libexec/armada/session-control" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/libexec/armada/start-plasma" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/libexec/os-session-select" 2>/dev/null || true
  chmod +x "$rootfs_dir/usr/share/gamescope-session-plus/sessions.d/steam" 2>/dev/null || true
}

enable_services() {
  ci_log "enabling gaming services"

  local wants_dir="$rootfs_dir/etc/systemd/system/multi-user.target.wants"
  install -d -m 0755 "$wants_dir"

  for svc in \
    inputplumber.service \
    plugin_loader.service; do
    if [ -f "$rootfs_dir/usr/lib/systemd/system/$svc" ]; then
      ln -sf "/usr/lib/systemd/system/$svc" "$wants_dir/$svc" 2>/dev/null || true
    elif [ -f "$rootfs_dir/etc/systemd/system/$svc" ]; then
      ln -sf "/etc/systemd/system/$svc" "$wants_dir/$svc" 2>/dev/null || true
    fi
  done
}

ci_log "starting gaming stack installation"

install_gaming_packages
install_fex_emu
install_proton
install_gamescope
install_mangohud
install_steam
install_inputplumber
install_decky_loader
install_system_files
enable_services

ci_log "gaming stack installation complete"
