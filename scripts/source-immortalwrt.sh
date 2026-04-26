#!/bin/bash
# ImmortalWrt source definition
# This file is sourced by scripts/build.sh

SOURCE_NAME="immortalwrt"
SOURCE_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
SOURCE_REPO_BRANCH="openwrt-24.10"
# Set AUTO_LATEST=true to auto-detect latest stable tag, false to use SOURCE_REPO_BRANCH
AUTO_LATEST=false

# Build dependencies for ImmortalWrt on Ubuntu/Debian
# Ref: https://github.com/immortalwrt/immortalwrt#requirements
SOURCE_BUILD_DEPS="ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd"

# Install build dependencies
install_deps() {
    log_info "Installing build dependencies for ${SOURCE_NAME}..."
    sudo -E apt-get -qq update
    # shellcheck disable=SC2086
    sudo -E apt-get -qq install -y ${SOURCE_BUILD_DEPS}
    log_ok "Dependencies installed"
}
