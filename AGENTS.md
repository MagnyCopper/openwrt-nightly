# AGENTS.md - OpenWrt Nightly Build Project

## 0. 项目愿景与需求

本项目是一个**通用的 OpenWrt 系列固件自动构建系统**，基于 GitHub Actions，需满足以下核心需求：

### 核心需求

| 需求 | 说明 | 当前状态 |
|------|------|---------|
| **多源码支持** | 支持 OpenWrt / ImmortalWrt / OpenRouter 等不同源码，可自由切换 | ⚠️ 架构就绪（build.yml input），仅 ImmortalWrt 已验证 |
| **多设备支持** | 支持 x86 / R2S / R4S 等不同设备，源码+设备可自由组合 | ⚠️ 架构就绪，当前仅 R2S |
| **同源码共享插件** | 同一源码下不同设备共享插件列表（`packages.conf`），允许个别设备有少量差异 | ✅ 已实现 |
| **并行矩阵构建** | 一次触发同时构建所有设备，利用 GitHub Actions matrix 策略 | ⚠️ 待实现 |
| **统一触发** | dev 推送 → 所有设备并行构建 Artifacts；main 定时 → 所有设备并行构建 Artifacts | ⚠️ 待实现矩阵 |
| **添加设备要简单** | 只需添加 `profiles/<device>/config`，不改 workflow | ✅ 已实现 |
| **零外部脚本** | 所有构建逻辑内联于 `build.yml`，不使用外部 shell 脚本 | ✅ 已实现 |
| **仅官方 Actions** | 仅使用 `actions/*` 官方包，清理操作使用 `gh` CLI | ✅ 已实现 |
| **合理拆分步骤** | 构建流程分为多个阶段，步骤清晰 | ✅ 已实现 |
| **优化缓存** | 仅缓存 `dl/` + `.ccache`（CCACHE_DIR 显式设置），clone 后恢复 | ✅ 已实现 |

### 待实现功能

1. **矩阵构建**：`dev-build.yml` / `biweekly-build.yml` 使用 `strategy.matrix` 并行构建多设备
2. **设备级插件差异**：允许 `profiles/<device>/packages.conf` 覆盖共享插件清单中的个别项

### 设计原则

- **Profile 为中心**：`profiles/<device>/` 是设备配置的唯一入口
- **源码无关**：源码参数通过 workflow input 传入，profile 不绑定源码
- **插件分层**：固件层 `configs/<source_name>/packages.conf` + 设备层 `profiles/<device>/config`
- **声明式配置**：尽量用 YAML 原生能力，不写脚本
- **仅官方 Actions**：仅使用 `actions/*` 官方包，清理用 `gh` CLI

---

## 1. Architecture

All build logic lives in `.github/workflows/build.yml` as native GitHub Actions steps. **No external scripts, no third-party actions.**

Only official `actions/*` are used:
- `actions/checkout@v4` — repository checkout
- `actions/cache@v4` — dl/ and .ccache caching
- `actions/upload-artifact@v4` — firmware artifact upload

Workflow run cleanup uses GitHub CLI (`gh`), no third-party action.

The workflow is a reusable workflow (`workflow_call`) called by:
- `dev-build.yml` → push to `dev` → artifacts (14-day retention)
- `biweekly-build.yml` → cron on `main` twice monthly (04:00 HKT on 2nd & 16th) → artifacts (14-day retention)

### Build Phases

| Phase | Step | What Happens |
|-------|------|-------------|
| 1 | Checkout + Env | Set BUILD_DATE, ARTIFACT_NAME |
| 2 | Free disk | Remove dotnet, android, CodeQL, docker images |
| 3 | Install deps | apt-get install build dependencies inline |
| 4 | Clone source | `git clone --depth=1` into `/workdir/openwrt` |
| 5 | Restore cache | **After clone** — restore `dl/` and `.ccache` (with CCACHE_DIR) |
| 6 | Feeds | 第三方 feed 按需 setup（仅 packages.conf 启用时添加）→ `feeds update -a` → `feeds install -a` |
| 7 | Load config | Device config + `configs/<source_name>/packages.conf` merge → `.config` |
| 8 | Download sources | `make defconfig && make download` + cleanup bad archives |
| 9 | Compile | Parallel → single thread → verbose retry cascade |
| 10 | Collect & upload | Firmware images + metadata → upload artifact |

## 2. Cache Strategy

**Only two caches, restored AFTER clone (safe):**

| Cache | Path | Key | Purpose |
|-------|------|-----|---------|
| dl | `/workdir/openwrt/dl` | `dl-{profile}-{branch}` | Downloaded source tarballs + Go module cache |
| ccache | `/workdir/openwrt/.ccache` | `ccache-{profile}-{branch}-{config_hash}` | Compilation cache |

**CCACHE_DIR is explicitly set** to `/workdir/openwrt/.ccache` before compilation to ensure the cache directory matches the `actions/cache` path.

**Why NO toolchain cache:**
- Source repos use `--depth=1` → new HEAD each build
- Toolchain intermediate files from old source cause `off64_t` errors
- ccache handles source changes gracefully without corruption risk

**Requirement:** `CONFIG_CCACHE=y` must be in the device config.

## 3. Profile System

```
profiles/<device>/
  config              # Device hardware config (target, device, drivers) + CONFIG_CCACHE=y
  files/              # Custom firmware files overlay (optional)
```

### Config Merging (分层配置)
1. `cp profiles/<device>/config .config` — 设备硬件配置
2. `awk` merge of `configs/<source_name>/packages.conf` — 该源码的共享插件清单（缺失则报错中止）。保留功能性 `# CONFIG_... is not set` 行（kconfig 指令非注释），跳过纯注释/空行
3. `make defconfig` — resolve dependencies

**基础镜像模式**：packages.conf 中注释行不会进入构建（merge 时 `grep -v` 过滤），用作插件暂存区——待验证插件注释保留，验证通过后取消注释推 dev 即启用。

**未来扩展**：允许 `profiles/<device>/packages.override` 增删个别插件

### Third-party feeds

第三方源按需添加（与 base-image mode 联动）：build.yml Feeds 阶段 grep `configs/<source_name>/packages.conf`，仅当对应插件未注释（=y）时才以 `src-git` 形式添加——当前登记两项：ddnsto（linkease/nas-packages + nas-packages-luci，staged 注释中故默认不拉取）与 luci-app-tailscale-community（Tokisaki-Galaxy，**staged：GUI 未真机验证，当前不拉取**；tailscale 后端本身来自 ImmortalWrt 官方 packages feed）。其余插件均自带于 ImmortalWrt 官方 feed（immortalwrt/luci + immortalwrt/packages）。新增第三方源沿用同一 grep 联动模式，参考 Section 7 的三种方式。

## 4. Source Configuration

Source parameters are workflow inputs (source-agnostic design):

```yaml
with:
  source_repo_url: 'https://github.com/immortalwrt/immortalwrt.git'  # 可切换源码
  source_branch: 'openwrt-24.10'                                     # 可切换分支
  source_name: 'immortalwrt'                                         # 显示名称
```

**支持的源码**（理论上）：
- ImmortalWrt: `https://github.com/immortalwrt/immortalwrt.git` branch `openwrt-24.10`
- OpenWrt 官方: `https://github.com/openwrt/openwrt.git` branch `v24.10.x`
- 其他 fork: 任意 Git URL + branch

## 5. Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/build.yml` | **核心引擎.** 单一可复用工作流，零脚本 |
| `.github/workflows/dev-build.yml` | Dev 触发器 (push to dev) |
| `.github/workflows/biweekly-build.yml` | Main 每月两次触发器 (cron + manual) |
| `configs/<source_name>/packages.conf` | 各源码的共享插件清单（同源码下所有设备共用，按 source_name 分目录） |
| `profiles/*/config` | 设备硬件配置 |
| `profiles/*/files/` | 固件 overlay 文件 (可选) |
| `RUNTIME-CHECKLIST.md` | 刷机后运行时手动清单（镜像刻意不含的 UU/共存补丁/认证项，分保留升级与全新刷入两场景） |

## 6. Common Pitfalls

- **Reusable Workflow Inputs**: Use `inputs.*` context, NOT `github.event.inputs.*`
- **Cache Before Clone**: NEVER restore cache before `git clone`. Always after.
- **Download Cleanup**: Only delete small archive files (`*.tar.*`, `*.zip`, `*.gz`), NOT Go module source files which can be tiny (e.g. protobuf `editiondefaults.binpb` = 154 bytes)
- **BOM Encoding**: All files must be UTF-8 WITHOUT BOM
- **"is not set" Lines Are Functional**: `# CONFIG_xxx is not set` is a kconfig directive, NOT a comment — the packages.conf merge (awk) must preserve it. Trap: with `CONFIG_ALL_KMODS=y`, kmod-tls defaults to m; its conditional dep `PACKAGE_kmod-tls:kmod-tls` then caps kmod-bonding at m (silently excluded from image) unless kmod-tls is explicitly not-set. Symptom: explicit `=y` lines demoted to `=m` after `make defconfig` — diff the defconfig output against the input to catch it.
- **LF Line Endings**: Enforced via `.gitattributes`
- **CCACHE needs DEVEL**: `CONFIG_CCACHE=y` is gated behind `CONFIG_DEVEL=y` (Config-devel.in: `bool "Use ccache" if DEVEL`). Without DEVEL, defconfig silently drops the symbol → 0MB ccache cache entries → every build cold. rules.mk defaults CCACHE_DIR to `$(TOPDIR)/.ccache`, matching the actions/cache path.
- **Action Versions**: Pin all `uses:` to specific tags (not `@master`/`@main`)
- **Files Overlay Destination**: `profiles/<device>/files/` contents MUST be copied to `<source>/files/` (OpenWrt rootfs overlay convention), NOT to the source-tree root — copying to root is silently ignored and scripts never ship
- **uci-defaults runs BEFORE procd services**: uci-defaults scripts execute during first-boot bootstrap, before services like tailscale (START=80) start. Any CLI-state config that needs a daemon socket (e.g. `tailscale set --advertise-routes`) will silently fail there (`|| true` hides it). Official pattern: put pure UCI in uci-defaults, and CLI-state application in a START=99 init.d that waits for the daemon socket (see `files/etc/init.d/tailscale-tune`).
- **hotplug.d Must Filter $ACTION/$DEVICE**: official hotplug spec delivers `$ACTION` (ifup/ifdown) and `$DEVICE` (kernel iface). Scripts without filtering fire on every event for every interface; guard with `[ "$ACTION" = "ifup" ]` and `case "$DEVICE" in eth0|eth1)`.
- **ethtool/Kernel-Driver State Is Not UCI-Persistable**: GRO/offload/ring-buffer settings are kernel runtime state via netlink — no UCI key exists by design. Persistence = hotplug.d (re-apply on ifup) + ship the `ethtool` package in packages.conf. Same class: RPS/RFS (/sys queues, init.d+hotplug), IRQ affinity, tc qdisc. sysctl IS persistable via /etc/sysctl.d.
- **Kernel Bump + Stale build_dir → kconfig (NEW) Failure**: after pulling source with a kernel version bump (e.g. 6.6.151→6.6.157), a stale `build_dir/.../linux-<old>` config lacks new symbols; syncconfig hits `(NEW)` prompts non-interactively and fails. Fix: `make target/linux/clean` then rebuild. If the symbol is genuinely missing from target config (check `target/linux/<target>/config-6.6`), add it (e.g. `CONFIG_ROCKCHIP_SARADC=m`).
- **Mid-Build .config Additions Need an Incremental Rerun**: enabling a new package while `make` is running does not add it to the current rootfs; after the build finishes, rerun `make -j2` (incremental, minutes) so the package compiles and the image is re-packed.
- **Manifest Diffs: ABI-Versioned Lib Names Are False Positives**: `packages.conf` says `libcurl` but the manifest lists `libcurl4` (also libbpf1/libelf1/libnghttp2-14/libreadline8/libruby3.3/libxtables12). Normalize ABI suffixes before declaring a package "missing".
- **Go Binaries Are Non-Deterministic Across Build Hosts**: same source version built locally vs upstream feed yields different sha256 (embedded build paths/timestamps). Verify by **version string**, not by hash, when comparing image binaries against an opkg-installed router.

## 7. Adding New Devices & Sources

### Adding a New Device

1. Create `profiles/<device>/config` with target, device, and `CONFIG_CCACHE=y`
   - Use `make menuconfig` in the source repo to generate the correct config
   - Example (R4S): `CONFIG_TARGET_rockchip=y` + `CONFIG_TARGET_rockchip_armv8=y` + `CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s=y`
2. Optionally add `profiles/<device>/files/` for custom overlay (uci-defaults scripts, config files)
3. (可选) 若该设备需要第三方软件源，在 `build.yml` Feeds 阶段按 profile/source_name 条件添加（当前 ImmortalWrt 无需）
4. Test with manual trigger: `gh workflow run dev-build.yml --ref dev -f profile=<device>`
5. (Future) Add to matrix in `dev-build.yml` / `biweekly-build.yml`

### Switching/Adding Source Repos

Source parameters are workflow inputs — **no changes to `build.yml` needed**:

```bash
# Example: build with official OpenWrt
gh workflow run dev-build.yml --ref dev \
  -f source_repo_url='https://github.com/openwrt/openwrt.git' \
  -f source_branch='v24.10.x' \
  -f source_name='openwrt'
```

**Caveats when switching sources:**
- Different sources have different default feeds → provide `configs/<source_name>/packages.conf` per source (build fails clearly if missing)
- Third-party feed compatibility varies by source → ImmortalWrt 通过 build.yml 的 feed 门控自动处理（当前登记 ddnsto 与 tailscale_luci，均 staged 不拉取）；其他源码按需在 Feeds 阶段添加
- Profile configs may need different kernel modules or drivers depending on the source

### Third-party Feed Patterns

Three patterns available (all inlined in `build.yml` Feeds phase). Current ImmortalWrt build uses the gated `src-git` pattern for ddnsto and tailscale_luci (both currently staged → feeds skipped):

| Pattern | When to Use | Example |
|---------|-------------|---------|
| `src-git` feed entry | Multi-package repos, need dependency resolution | `echo "src-git feedname https://github.com/user/repo.git;branch" >> feeds.conf.default` |
| `git clone` to `package/` | Standalone data packages, no feed deps needed | `git clone --depth=1 https://github.com/user/repo.git package/repo-name` |
| Feed override + reinstall | Replace built-in packages with custom versions | `rm -rf feeds/packages/lang/<pkg>` → clone replacement → `feeds update -i packages` → `feeds install -f -p packages <pkg>` |

## 8. Debugging Failed Builds

- Check the **Compile firmware** step for the actual error
- The retry cascade provides verbose output: `make -j1 V=s`
- If `No space left on device` → check disk cleanup step
- If `no required module provides package` → check download cleanup step didn't delete Go module files
- To debug interactively: add `tmate` SSH step to build.yml temporarily (not included by default to avoid third-party deps)

## 9. Router Change Workflow (Gates & Parity)

Changes to router configuration/scripts follow a **gated pipeline** — every stage transition requires explicit user approval:

1. **Runtime functional validation** on the production router (apply via UCI/live, test behavior).
2. **Codify** into the `immortalwrt-r2s/files/` overlay → local build → verify rootfs contents + manifest.
3. **Offline image inspection** — unsquashfs the sysupgrade image and verify files/bins on the workstation. Never use the production router as a test bench for flashing; it is in daily use and flashing is rare, user-initiated maintenance only.
4. **Port to this repo** (`profiles/<device>/files/` + `packages.conf`) → push `dev` → CI build validates.

### Parity rule

Live-router custom config must stay mirrored in the `immortalwrt-r2s/files/` overlay — same files, same content, sha256-verified three ways (overlay == image rootfs == live router). Documented exceptions (runtime-restored, deliberately not in firmware): UU plugin files (official install.sh rebinds by MAC), OpenClash runtime config (gist subscription), Tailscale auth (interactive; state preserved on kept-config sysupgrade via official `lib/upgrade/keep.d/tailscale`).

### Reference implementations (validated 2026-10-10/11 on live R2S)

- `files/etc/uci-defaults/99-tailscale-firewall` — pure-UCI first-boot config (fw4 zone/forwarding/rule + OpenClash CGNAT bypass)
- `files/etc/init.d/tailscale-tune` — START=99 CLI-state pattern (advertise LAN subnet derived via ipcalc.sh; waits for daemon socket)
- `files/etc/hotplug.d/iface/98-gro-forwarding` — $DEVICE-filtered hotplug re-apply pattern for kernel driver state (UDP GRO per tailscale.com/kb/1777)

Verification record: three-way sha256 parity confirmed; LuCI reachable via Tailscale (fw4 counter 167+ packets); second LAN device reachable from iPad; UU/OpenClash untouched and healthy.
