#!/bin/bash
set -euo pipefail

# ============================================
# OpenWrt Source Build Script
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${GITHUB_WORKSPACE:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
OPENWRT_ROOT="/workdir/openwrt"

# Source utilities
source "${SCRIPT_DIR}/common.sh"

# ============================================
# Phase 0: Load Configuration
# ============================================
load_config() {
    local profile="${1:?Profile name required}"
    local source_file="${2:-source-immortalwrt.sh}"

    export PROFILE="${profile}"
    export PROFILE_DIR="${WORKSPACE}/profiles/${profile}"

    if [[ ! -d "${PROFILE_DIR}" ]]; then
        log_error "Profile directory not found: ${PROFILE_DIR}"
        exit 1
    fi

    # Source the source definition
    source "${SCRIPT_DIR}/${source_file}"

    # Determine the branch/tag to build
    if [[ "${AUTO_LATEST}" == "true" ]]; then
        local latest_tag
        latest_tag=$(get_latest_release "immortalwrt/immortalwrt")
        if [[ -n "${latest_tag}" ]]; then
            export SOURCE_REPO_BRANCH="${latest_tag}"
            log_info "Auto-detected latest release: ${latest_tag}"
        fi
    fi

    log_info "============================================"
    log_info "Build Configuration"
    log_info "============================================"
    log_info "Source:      ${SOURCE_NAME} (${SOURCE_REPO_URL})"
    log_info "Branch/Tag:  ${SOURCE_REPO_BRANCH}"
    log_info "Profile:     ${PROFILE}"
    log_info "Profile Dir: ${PROFILE_DIR}"
    log_info "============================================"
}

# ============================================
# Phase 1: Environment Setup
# ============================================
setup_environment() {
    log_info "Setting up build environment..."

    cleanup_runner
    install_deps

    sudo timedatectl set-timezone "Asia/Shanghai" 2>/dev/null || \
        sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    sudo mkdir -p /workdir
    sudo chown "${USER}:${GROUPS}" /workdir

    log_ok "Environment setup complete"
}

# ============================================
# Phase 2: Source Code Preparation
# ============================================
clone_source() {
    log_info "Cloning source code: ${SOURCE_REPO_URL} @ ${SOURCE_REPO_BRANCH}"

    if [[ -d "${OPENWRT_ROOT}" ]]; then
        log_info "Source directory exists, removing..."
        rm -rf "${OPENWRT_ROOT}"
    fi

    git clone --depth=1 --single-branch -b "${SOURCE_REPO_BRANCH}" \
        "${SOURCE_REPO_URL}" "${OPENWRT_ROOT}"

    # Create symlink for convenience
    ln -sf "${OPENWRT_ROOT}" "${WORKSPACE}/openwrt"

    log_ok "Source code cloned"
    cd "${OPENWRT_ROOT}"
}

# ============================================
# Phase 3: Feeds & Customization
# ============================================
update_feeds() {
    log_info "Updating and installing feeds..."
    cd "${OPENWRT_ROOT}"

    # Run pre-build hook (can add custom feeds, etc.)
    local hook="${PROFILE_DIR}/hooks/pre-build.sh"
    if [[ -f "${hook}" ]]; then
        log_info "Running pre-build hook..."
        chmod +x "${hook}"
        "${hook}"
    fi

    ./scripts/feeds update -a
    ./scripts/feeds install -a

    log_ok "Feeds updated and installed"
}

load_config_file() {
    log_info "Loading device configuration..."
    cd "${OPENWRT_ROOT}"

    # Copy custom files
    if [[ -d "${PROFILE_DIR}/files" ]]; then
        mkdir -p files
        cp -r "${PROFILE_DIR}/files/"* "${OPENWRT_ROOT}/files/" 2>/dev/null || true
        log_ok "Custom files copied"
    fi

    # Copy .config
    if [[ -f "${PROFILE_DIR}/config" ]]; then
        cp "${PROFILE_DIR}/config" "${OPENWRT_ROOT}/.config"
        log_ok "Device config loaded"
    else
        log_error "No config file found at ${PROFILE_DIR}/config"
        exit 1
    fi
}

# ============================================
# Phase 4: Build
# ============================================
download_sources() {
    log_info "Downloading source packages..."
    cd "${OPENWRT_ROOT}"

    make defconfig
    make download -j"$(nproc)"

    # Check for failed downloads (files < 1024 bytes are likely errors)
    find dl -size -1024c -exec ls -l {} \;
    find dl -size -1024c -exec rm -f {} \;

    log_ok "Source packages downloaded"
}

compile_firmware() {
    log_info "Compiling firmware ($(nproc) threads)..."
    cd "${OPENWRT_ROOT}"

    # First attempt: parallel build
    if ! make -j"$(nproc)"; then
        log_warn "Parallel build failed, retrying with single thread..."
        # Second attempt: single thread
        if ! make -j1; then
            log_warn "Single thread build failed, retrying with verbose output..."
            # Third attempt: verbose single thread for debugging
            make -j1 V=s
        fi
    fi

    log_ok "Firmware compiled successfully"
}

# ============================================
# Phase 5: Post-Build
# ============================================
post_build() {
    log_info "Running post-build tasks..."
    cd "${OPENWRT_ROOT}"

    # Detect device name from config
    grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/' > DEVICE_NAME
    local device_name
    device_name=$(cat DEVICE_NAME 2>/dev/null || echo "unknown")

    # Run post-build hook
    local hook="${PROFILE_DIR}/hooks/post-build.sh"
    if [[ -f "${hook}" ]]; then
        chmod +x "${hook}"
        "${hook}"
    fi

    log_ok "Post-build complete. Device: ${device_name}"
}

collect_firmware() {
    log_info "Collecting firmware files..."
    cd "${OPENWRT_ROOT}"

    local firmware_dir="${WORKSPACE}/firmware"
    mkdir -p "${firmware_dir}"

    # Find and copy firmware images
    find bin/targets -type f \( -name "*.img.gz" -o -name "*.img" -o -name "*.bin" -o -name "*.itb" \) \
        -exec cp {} "${firmware_dir}/" \;

    # Also copy sha256sums if available
    find bin/targets -name "sha256sums" -exec cp {} "${firmware_dir}/" \;

    log_ok "Firmware files collected:"
    ls -lh "${firmware_dir}/"

    echo "FIRMWARE_DIR=${firmware_dir}" >> "${GITHUB_ENV:-/dev/null}"
}

# ============================================
# Main Entry Point
# ============================================
main() {
    local command="${1:-all}"
    local profile="${2:-r2s}"
    local source_file="${3:-source-immortalwrt.sh}"

    case "${command}" in
        all)
            load_config "${profile}" "${source_file}"
            setup_environment
            clone_source
            update_feeds
            load_config_file
            download_sources
            compile_firmware
            post_build
            collect_firmware
            ;;
        load-config)
            load_config "${profile}" "${source_file}"
            ;;
        setup)
            load_config "${profile}" "${source_file}"
            setup_environment
            ;;
        clone)
            load_config "${profile}" "${source_file}"
            clone_source
            ;;
        feeds)
            load_config "${profile}" "${source_file}"
            update_feeds
            ;;
        config)
            load_config "${profile}" "${source_file}"
            load_config_file
            ;;
        download)
            load_config "${profile}" "${source_file}"
            download_sources
            ;;
        compile)
            load_config "${profile}" "${source_file}"
            compile_firmware
            ;;
        post-build)
            load_config "${profile}" "${source_file}"
            post_build
            collect_firmware
            ;;
        *)
            echo "Usage: $0 {all|setup|clone|feeds|config|download|compile|post-build} [profile] [source_file]"
            echo "  profile:     Device profile name (default: r2s)"
            echo "  source_file: Source definition script (default: source-immortalwrt.sh)"
            exit 1
            ;;
    esac
}

main "$@"
