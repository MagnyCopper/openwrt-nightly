#!/bin/bash
# Pre-build hook for R2S profile
# Adds third-party feeds and overrides before feeds update/install
# This runs AFTER git clone, BEFORE feeds update

set -e

# --- DDNSTo (linkease/nas-packages) ---
echo "src-git ddnsto https://github.com/linkease/nas-packages.git" >> feeds.conf.default
echo "src-git ddnsto_luci https://github.com/linkease/nas-packages-luci.git" >> feeds.conf.default

# --- MosDNS v5 (sbwml/luci-app-mosdns) ---
# Clone into package/ dir for direct inclusion (overrides feed version)
git clone --depth=1 -b v5 https://github.com/sbwml/luci-app-mosdns.git package/luci-app-mosdns
git clone --depth=1 https://github.com/sbwml/v2ray-geodata.git package/v2ray-geodata

# --- Golang toolchain (24.x for mosdns) ---
# Must replace AFTER feeds update, so we mark it for the workflow step
touch /tmp/.golang-override
