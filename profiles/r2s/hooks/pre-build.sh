#!/bin/bash
# Pre-build hook for R2S profile
# Runs before feeds update/install, use this to add third-party feeds

set -e

# --- DDNSTo (linkease/nas-packages) ---
echo "src-git ddnsto https://github.com/linkease/nas-packages.git" >> feeds.conf.default
echo "src-git ddnsto_luci https://github.com/linkease/nas-packages-luci.git" >> feeds.conf.default

# --- MosDNS v5 (sbwml/luci-app-mosdns) ---
# Remove old mosdns from feeds/packages so our version takes priority
# (feeds update will re-create this, but feeds install -f will override)
sed -i '/^src-git.*mosdns/d' feeds.conf.default

# v2ray-geodata replacement (put in package/ dir for direct inclusion)
rm -rf feeds/packages/net/v2ray-geodata 2>/dev/null
git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata

# mosdns v5 + luci app (clone into package/ dir for direct inclusion)
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns.git package/luci-app-mosdns

# Signal that golang toolchain needs overriding (done after feeds update in build.yml)
touch /tmp/.r2s-golang-override

log_info "R2S pre-build hook: added ddnsto + mosdns feeds" 2>/dev/null || echo "R2S pre-build hook: added ddnsto + mosdns feeds"
