#!/bin/bash
# Common utility functions for OpenWrt build system

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Free up disk space on GitHub Actions runner
cleanup_runner() {
    log_info "Cleaning up runner disk space..."
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL
    sudo docker image prune --all --force 2>/dev/null || true
    sudo -E apt-get -qq autoremove --purge
    sudo -E apt-get -qq clean
    df -hT /
}

# Detect the latest stable release tag for a GitHub repo
# Usage: get_latest_release "immortalwrt/immortalwrt"
get_latest_release() {
    local repo="$1"
    git ls-remote --tags --sort=-v:refname "https://github.com/${repo}.git" \
        | grep -v '\^{}' \
        | grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
        | head -1 \
        | awk -F'/' '{print $NF}'
}

# Set build metadata as environment variables
set_build_metadata() {
    local profile="$1"
    local source_name="$2"

    export BUILD_DATE=$(date +"%Y.%m.%d")
    export BUILD_TIMESTAMP=$(date +"%Y%m%d%H%M")
    export ARTIFACT_NAME="${source_name}-${profile}-${BUILD_DATE}"
    export RELEASE_TAG="v${BUILD_DATE}-${BUILD_TIMESTAMP}"

    log_info "Build Date: ${BUILD_DATE}"
    log_info "Artifact Name: ${ARTIFACT_NAME}"
    log_info "Release Tag: ${RELEASE_TAG}"
}
