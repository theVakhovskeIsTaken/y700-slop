#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

cat <<'INFO'
Local build script for Y700 Armada OS
======================================

This builds the rootfs (from Armada container image) and GRUB images locally.
Prerequisites: podman, dosfstools, mtools, e2fsprogs, rsync, podman

INFO

export OUTPUT_DIR_ROOTFS="out/ci-rootfs"
export OUTPUT_DIR_GRUB="out/ci-grub"
export OUTPUT_PREFIX="y700-armada-os"

export ARMADA_IMAGE="ghcr.io/armada-os/armada:testing"

export ROOTFS_IMAGE_SIZE=24G
export ROOTFS_UUID=
export ROOTFS_LABEL=Armada
export ROOTFS_PARTLABEL=userdata
export HOSTNAME_NAME=y700
export DEFAULT_USER_NAME=armada
export DEFAULT_USER_PASSWORD=deck

export DEVICE_DEB_ARCHIVE=https://github.com/GUF296/ubuntu-y700-build-ci/releases/download/bootstrap-y700-20260625/y700-device-debs-20260624-201420-compat1.tar.gz
export SENSOR_DEB_DIR=
export HAPTICS_DEB_DIR=
export CAMERA_STACK_DEB_DIR=

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

export APPLY_Y700_FIRMWARE_FIXES=1
export APPLY_Y700_AUDIO_POLICY_FIXES=1
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

echo "Building sensor debs..."
if [ "${BUILD_Y700_SENSOR_DEBS:-0}" = "1" ]; then
  if [ -z "${SENSOR_SOURCE_ARCHIVE:-}" ] && [ -z "${SENSOR_SOURCE_DIR:-}" ] && [ -n "${SENSOR_DEB_ARCHIVE:-}" ]; then
    echo "Using prebuilt sensor debs; skipping source build."
    Y700_SENSOR_DEB_DIR=
  else
    env OUTPUT_DIR="out/y700-sensor-debs" \
      ARCH="arm64" \
      SENSOR_DEB_VERSION="$SENSOR_DEB_VERSION" \
      SENSOR_SOURCE_ARCHIVE="$SENSOR_SOURCE_ARCHIVE" \
      SENSOR_BASELINE_OVERLAY_ARCHIVE="$SENSOR_BASELINE_OVERLAY_ARCHIVE" \
      SENSOR_STRIP="$SENSOR_STRIP" \
      bash "$SCRIPT_DIR/scripts/ci/build-y700-sensor-debs.sh"
    Y700_SENSOR_DEB_DIR=out/y700-sensor-debs
  fi
else
  Y700_SENSOR_DEB_DIR=
fi

echo "Building haptics deb..."
if [ "${BUILD_TB321FU_HAPTICS_DEB:-0}" = "1" ]; then
  if [ -z "${HAPTICS_SOURCE_ARCHIVE:-}" ] && [ -z "${HAPTICS_SOURCE_DIR:-}" ] && [ -n "${HAPTICS_DEB_ARCHIVE:-}" ]; then
    echo "Using prebuilt haptics deb; skipping source build."
    TB321FU_HAPTICS_DEB_DIR=
  else
    env OUTPUT_DIR="out/tb321fu-haptics-debs" \
      ARCH="arm64" \
      HAPTICS_DEB_VERSION="$HAPTICS_DEB_VERSION" \
      HAPTICS_SOURCE_ARCHIVE="$HAPTICS_SOURCE_ARCHIVE" \
      KERNEL_SOURCE_ARCHIVE="$KERNEL_SOURCE_ARCHIVE" \
      KERNEL_BUILD_ARCHIVE="$KERNEL_BUILD_ARCHIVE" \
      HAPTICS_STRIP="$HAPTICS_STRIP" \
      bash "$SCRIPT_DIR/scripts/ci/build-tb321fu-haptics-deb.sh"
    TB321FU_HAPTICS_DEB_DIR=out/tb321fu-haptics-debs
  fi
else
  TB321FU_HAPTICS_DEB_DIR=
fi

echo "Building camera stack deb..."
if [ "${BUILD_TB321FU_CAMERA_STACK:-0}" = "1" ]; then
  if [ -z "${CAMERA_STACK_ARCHIVE:-}" ] && [ -z "${CAMERA_STACK_DIR:-}" ]; then
    echo "Using source camera stack overlay."
  fi
  env OUTPUT_DIR="out/tb321fu-camera-stack-debs" \
    ARCH="arm64" \
    CAMERA_STACK_DEB_VERSION="$CAMERA_STACK_DEB_VERSION" \
    CAMERA_STACK_ARCHIVE="$CAMERA_STACK_ARCHIVE" \
    CAMERA_STACK_DIR="$CAMERA_STACK_DIR" \
    bash "$SCRIPT_DIR/scripts/ci/build-tb321fu-camera-stack-deb.sh"
  TB321FU_CAMERA_STACK_DEB_DIR=out/tb321fu-camera-stack-debs
else
  TB321FU_CAMERA_STACK_DEB_DIR=
fi

echo "Starting Armada rootfs build..."
sudo --preserve-env=ARMADA_IMAGE,ROOTFS_IMAGE_SIZE,ROOTFS_UUID,ROOTFS_LABEL,ROOTFS_PARTLABEL,HOSTNAME_NAME,DEFAULT_USER_NAME,DEFAULT_USER_PASSWORD,DEVICE_DEB_ARCHIVE,SENSOR_DEB_DIR,HAPTICS_DEB_DIR,CAMERA_STACK_DEB_DIR,BUILD_TB321FU_GPU_SENSOR,TB321FU_GPU_SENSOR_SOURCE_DIR,TB321FU_GPU_SENSOR_BUILD_JOBS,APPLY_Y700_FIRMWARE_FIXES,APPLY_Y700_AUDIO_POLICY_FIXES,COMPRESS,CHUNK_SIZE,KEEP_RAW_IMAGE \
  env OUTPUT_DIR="$OUTPUT_DIR_ROOTFS" \
      SENSOR_DEB_DIR="${Y700_SENSOR_DEB_DIR:-${SENSOR_DEB_DIR:-}}" \
      HAPTICS_DEB_DIR="${TB321FU_HAPTICS_DEB_DIR:-${HAPTICS_DEB_DIR:-}}" \
      CAMERA_STACK_DEB_DIR="${TB321FU_CAMERA_STACK_DEB_DIR:-}" \
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
