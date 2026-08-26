#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

cat <<'INFO'
Local build script for Y700 Armada Gaming Stack
=================================================

This builds the rootfs and GRUB images locally.
Prerequisites: debootstrap, dosfstools, mtools, e2fsprogs, rsync, podman/docker

INFO

export OUTPUT_DIR_ROOTFS="out/ci-rootfs"
export OUTPUT_DIR_GRUB="out/ci-grub"
export OUTPUT_PREFIX="y700-armada-gaming"

export DISTRO=resolute
export ARCH=arm64
export MIRROR=http://ports.ubuntu.com/ubuntu-ports
export DEBOOTSTRAP_VARIANT=

export ROOTFS_IMAGE_SIZE=24G
export ROOTFS_UUID=
export ROOTFS_LABEL=Ubuntu
export ROOTFS_PARTLABEL=userdata
export HOSTNAME_NAME=y700
export DEFAULT_USER_NAME=y700
export DEFAULT_USER_PASSWORD=1234
export ROOT_PASSWORD_MODE=locked
export ROOT_PASSWORD=
export USER_SUDO_MODE=password
export SDDM_AUTOLOGIN=1
export SDDM_AUTOLOGIN_SESSION=plasma
export TZ_REGION=Asia/Shanghai
export LANG_NAME=zh_CN.UTF-8
export LOCALES=$'en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8'

export PACKAGE_LIST=
export DESKTOP_ENV=kubuntu-desktop
export OVERLAY_ARCHIVE=
export DEB_ARCHIVE=https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz

export BUILD_Y700_SENSOR_DEBS=1
export SENSOR_DEB_ARCHIVE=https://github.com/GUF296/tb321fu-sensor-debs/releases/download/tb321fu-sensor-debs-20260627.1/tb321fu-sensor-debs_20260627.1_arm64.tar.gz
export SENSOR_SOURCE_ARCHIVE=
export SENSOR_BASELINE_OVERLAY_ARCHIVE=
export SENSOR_DEB_VERSION=20260627.1
export SENSOR_STRIP=1

export BUILD_TB321FU_HAPTICS_DEB=1
export HAPTICS_DEB_ARCHIVE=https://github.com/GUF296/tb321fu-haptics-debs/releases/download/tb321fu-haptics-debs-20260627.2/tb321fu-haptics-debs_20260627.2_arm64.tar.gz
export HAPTICS_SOURCE_ARCHIVE=
export KERNEL_SOURCE_ARCHIVE=
export KERNEL_BUILD_ARCHIVE=
export HAPTICS_DEB_VERSION=20260627.2
export HAPTICS_STRIP=1

export BUILD_TB321FU_CAMERA_STACK=1
export CAMERA_STACK_ARCHIVE=
export CAMERA_STACK_DIR=
export CAMERA_STACK_DEB_VERSION=20260627.4

export BUILD_TB321FU_GPU_SENSOR=1
export TB321FU_GPU_SENSOR_SOURCE_DIR=
export TB321FU_GPU_SENSOR_BUILD_JOBS=2

export INSTALL_GAMING_STACK=1
export STEAM_CLIENT_URL=
export STEAM_RUNTIME_URL=
export FEX_EMU_VERSION=FEX-2608
export FEX_ROOTFS_URL=https://rootfs.fex-emu.gg/ArchLinux/2026-08-11/ArchLinux.sqsh
export PROTON_URL=https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20260703-slr/proton-cachyos-11.0-20260703-slr-arm64.tar.xz
export GAMESCOPE_URL=
export GAMESCOPE_SESSION_URL=https://github.com/OpenGamingCollective/gamescope-session-steam/archive/refs/heads/main.tar.gz
export MANGOHUD_URL=
export DECKY_LOADER_URL=https://github.com/SteamDeckHomebrew/decky-loader/releases/download/v3.2.6/PluginLoader
export INPUTPLUMBER_URL=https://github.com/ShadowBlip/InputPlumber/releases/download/v0.78.1/inputplumber_0.78.1-1_arm64.deb

export INSTALL_GNOME_SNAPSHOT=1
export INSTALL_FIREFOX=1
export INSTALL_FCITX5_CHINESE=1
export FCITX5_CHINESE_PACKAGES="fonts-noto-cjk im-config fcitx5 fcitx5-chinese-addons fcitx5-pinyin fcitx5-config-qt kde-config-fcitx5 fcitx5-frontend-gtk2 fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 fcitx5-frontend-qt6 fcitx5-module-wayland fcitx5-module-xorg fcitx5-module-kimpanel fcitx5-module-emoji fcitx5-material-color"
export DISABLE_SNAPD=1
export APPLY_Y700_FIRMWARE_FIXES=1
export APPLY_Y700_AUDIO_POLICY_FIXES=1
export CLEAN_APT_CACHE=1
export COMPRESS=7z
export CHUNK_SIZE=
export KEEP_RAW_IMAGE=0

export BOOT_TEMPLATE_IMAGE=https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-verified-grub-template-userdata-20260624-201420.img
export BOOT_FAT_BITS=32
export BOOT_FAT_LABEL=Y700GRUB
export BOOT_SECTOR_SIZE=512
export BOOT_CLUSTER_SECTORS=
export ROOT_SELECTOR=partlabel
export ROOT_UUID=
export ROOT_PARTLABEL=userdata
export ROOTARGS=
export ROOTARGS_EXTRA=
export STABLEARGS=drm_client_lib.active=none
export BOOT_COMPRESS=7z
export BOOT_CHUNK_SIZE=
export KEEP_BOOT_IMAGE=0

export KERNEL_ARTIFACT_ARCHIVE=https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-kernel-artifacts-7.1.1-g5df8e852ea72.tar.gz
export BOOTAA64_EFI_URL=
export QCOMRAMP_EFI_URL=
export QCOMRAMP_CFG_NAME=qcomramp.cfg
export GRUB_BUILD_ARCHIVE=
export DTB_NAME=sm8650-lenovo-tb321fu.dtb

mkdir -p "$OUTPUT_DIR_ROOTFS" "$OUTPUT_DIR_GRUB"

echo "Starting rootfs build..."
sudo --preserve-env=OUTPUT_PREFIX,DISTRO,ARCH,MIRROR,DEBOOTSTRAP_VARIANT,RESOLV_CONF_CONTENT,APT_HTTP_PROXY,APT_HTTPS_PROXY,http_proxy,https_proxy,HTTP_PROXY,HTTPS_PROXY,APT_SOURCES_LIST,ROOTFS_IMAGE_SIZE,ROOTFS_UUID,ROOTFS_LABEL,ROOTFS_PARTLABEL,HOSTNAME_NAME,DEFAULT_USER_NAME,DEFAULT_USER_PASSWORD,ROOT_PASSWORD_MODE,ROOT_PASSWORD,USER_SUDO_MODE,SDDM_AUTOLOGIN,SDDM_AUTOLOGIN_SESSION,TZ_REGION,LOCALES,LANG_NAME,PACKAGE_LIST,DESKTOP_ENV,OVERLAY_ARCHIVE,DEB_ARCHIVE,DEB_DIR,SENSOR_DEB_ARCHIVE,SENSOR_DEB_DIR,HAPTICS_DEB_ARCHIVE,HAPTICS_DEB_DIR,CAMERA_STACK_DEB_DIR,BUILD_TB321FU_GPU_SENSOR,TB321FU_GPU_SENSOR_SOURCE_DIR,TB321FU_GPU_SENSOR_BUILD_JOBS,INSTALL_GAMING_STACK,STEAM_CLIENT_URL,STEAM_RUNTIME_URL,FEX_EMU_VERSION,FEX_ROOTFS_URL,PROTON_URL,GAMESCOPE_URL,GAMESCOPE_SESSION_URL,MANGOHUD_URL,DECKY_LOADER_URL,INPUTPLUMBER_URL,INSTALL_GNOME_SNAPSHOT,INSTALL_FIREFOX,INSTALL_FCITX5_CHINESE,FCITX5_CHINESE_PACKAGES,DISABLE_SNAPD,APPLY_Y700_FIRMWARE_FIXES,APPLY_Y700_AUDIO_POLICY_FIXES,CLEAN_APT_CACHE,COMPRESS,CHUNK_SIZE,KEEP_RAW_IMAGE \
  env OUTPUT_DIR="$OUTPUT_DIR_ROOTFS" \
  bash "$SCRIPT_DIR/scripts/ci/build-rootfs-image.sh"

sudo chown -R "$(id -u):$(id -g)" out

echo "Starting GRUB boot image build..."
env OUTPUT_DIR="$OUTPUT_DIR_GRUB" \
  OUTPUT_PREFIX="$OUTPUT_PREFIX" \
  BOOT_TEMPLATE_IMAGE="$BOOT_TEMPLATE_IMAGE" \
  BOOT_IMAGE_SIZE=256M \
  BOOT_FAT_BITS="$BOOT_FAT_BITS" \
  BOOT_FAT_LABEL="$BOOT_FAT_LABEL" \
  BOOT_SECTOR_SIZE="$BOOT_SECTOR_SIZE" \
  BOOT_CLUSTER_SECTORS="$BOOT_CLUSTER_SECTORS" \
  KERNEL_ARTIFACT_ARCHIVE="$KERNEL_ARTIFACT_ARCHIVE" \
  BOOTAA64_EFI_URL="$BOOTAA64_EFI_URL" \
  QCOMRAMP_EFI_URL="$QCOMRAMP_EFI_URL" \
  QCOMRAMP_CFG_NAME="$QCOMRAMP_CFG_NAME" \
  DTB_NAME="$DTB_NAME" \
  ROOT_SELECTOR="$ROOT_SELECTOR" \
  ROOT_PARTLABEL="$ROOT_PARTLABEL" \
  ROOT_UUID="$ROOT_UUID" \
  ROOTARGS="$ROOTARGS" \
  ROOTARGS_EXTRA="$ROOTARGS_EXTRA" \
  STABLEARGS="$STABLEARGS" \
  BOOT_COMPRESS="$BOOT_COMPRESS" \
  BOOT_CHUNK_SIZE="$BOOT_CHUNK_SIZE" \
  KEEP_BOOT_IMAGE="$KEEP_BOOT_IMAGE" \
  bash "$SCRIPT_DIR/scripts/ci/build-grub-image.sh"

echo ""
echo "Build complete!"
echo "Rootfs: $OUTPUT_DIR_ROOTFS/${OUTPUT_PREFIX}-rootfs.img*"
echo "GRUB:   $OUTPUT_DIR_GRUB/${OUTPUT_PREFIX}-grub-fat.img*"
