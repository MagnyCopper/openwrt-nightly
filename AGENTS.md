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
- `biweekly-build.yml` → cron on `main` twice monthly (1st & 15th) → artifacts (14-day retention)

### Build Phases

| Phase | Step | What Happens |
|-------|------|-------------|
| 1 | Checkout + Env | Set BUILD_DATE, ARTIFACT_NAME |
| 2 | Free disk | Remove dotnet, android, CodeQL, docker images |
| 3 | Install deps | apt-get install build dependencies inline |
| 4 | Clone source | `git clone --depth=1` into `/workdir/openwrt` |
| 5 | Restore cache | **After clone** — restore `dl/` and `.ccache` (with CCACHE_DIR) |
| 6 | Feeds | ddnsto 第三方源 setup → `feeds update -a` → `feeds install -a`（其余插件均 ImmortalWrt 自带）|
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
2. `grep -v '^\s*#' configs/<source_name>/packages.conf | grep -v '^\s*$' >> .config` — 该源码的共享插件清单（缺失则报错中止）
3. `make defconfig` — resolve dependencies

**未来扩展**：允许 `profiles/<device>/packages.override` 增删个别插件

### Third-party feeds

当前仅 ddnsto 需要第三方源（linkease/nas-packages + nas-packages-luci），已在 build.yml Feeds 阶段自动以 `src-git` 形式添加，无 profile/source 闸门（跨设备生效）。其余插件均自带于 ImmortalWrt 官方 feed（immortalwrt/luci + immortalwrt/packages）。若未来需要更多第三方源，参考 Section 7 的三种模式。

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

## 6. Common Pitfalls

- **Reusable Workflow Inputs**: Use `inputs.*` context, NOT `github.event.inputs.*`
- **Cache Before Clone**: NEVER restore cache before `git clone`. Always after.
- **Download Cleanup**: Only delete small archive files (`*.tar.*`, `*.zip`, `*.gz`), NOT Go module source files which can be tiny (e.g. protobuf `editiondefaults.binpb` = 154 bytes)
- **BOM Encoding**: All files must be UTF-8 WITHOUT BOM
- **LF Line Endings**: Enforced via `.gitattributes`
- **CCACHE_DIR**: Must be set explicitly; OpenWrt doesn't default to `.ccache` in source root
- **Action Versions**: Pin all `uses:` to specific tags (not `@master`/`@main`)

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
- Third-party feed compatibility varies by source → ImmortalWrt 当前仅需 ddnsto（已自动配置）；其他源码按需在 Feeds 阶段添加
- Profile configs may need different kernel modules or drivers depending on the source

### Third-party Feed Patterns

Three patterns available (all inlined in `build.yml` Feeds phase). Current ImmortalWrt build uses none:

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
