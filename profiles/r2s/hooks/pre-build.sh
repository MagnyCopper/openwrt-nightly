#!/bin/bash
# Pre-build hook for R2S profile
# Runs before feeds update/install, use this to add third-party feeds

set -e

# --- DDNSTo (linkease/nas-packages) ---
echo "src-git ddnsto https://github.com/linkease/nas-packages.git" >> feeds.conf.default
echo "src-git ddnsto_luci https://github.com/linkease/nas-packages-luci.git" >> feeds.conf.default

# --- MosDNS (sbwml/luci-app-mosdns v5) ---
# mosdns needs its own package dir + v2ray-geodata + updated golang toolchain
rm -rf feeds/packages/net/v2ray-geodata
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns.git package/mosdns
git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata

# Update golang toolchain for mosdns (requires Go 1.24+)
rm -rf feeds/packages/lang/golang
git clone --depth=1 -b 24.x https://github.com/sbwml/packages_lang_golang.git feeds/packages/lang/golang

log_info "R2S pre-build hook: added ddnsto + mosdns feeds" 2>/dev/null || echo "R2S pre-build hook: added ddnsto + mosdns feeds"
