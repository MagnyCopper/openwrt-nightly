#!/bin/bash
# Pre-build hook for R2S profile
# Runs after feeds install, before build

# Example: Add a custom feed
# echo "src-git custom https://github.com/your-repo/packages.git" >> feeds.conf.default

# Example: Apply a patch
# patch -p1 < "${PROFILE_DIR}/patches/some-fix.patch"

log_info "R2S pre-build hook executed"
