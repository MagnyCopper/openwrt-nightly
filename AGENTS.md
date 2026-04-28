# AGENTS.md - OpenWrt Nightly Build Project

## 0. 项目愿景与需求

本项目是一个**通用的 OpenWrt 系列固件自动构建系统**，基于 GitHub Actions，需满足以下核心需求：

### 核心需求

| 需求 | 说明 | 当前状态 |
|------|------|---------|
| **多源码支持** | 支持 OpenWrt / ImmortalWrt / OpenRouter 等不同源码，可自由切换 | ✅ 已实现（workflow input） |
| **多设备支持** | 支持 x86 / R2S / R4S 等不同设备，源码+设备可自由组合 | ⚠️ 架构就绪，当前仅 R2S |
| **同源码共享插件** | 同一源码下不同设备共享插件列表（`packages.conf`），允许个别设备有少量差异 | ✅ 已实现 |
| **并行矩阵构建** | 一次触发同时构建所有设备，利用 GitHub Actions matrix 策略 | ⚠️ 待实现 |
| **统一触发** | dev 推送 → 所有设备并行构建 Artifacts；main 定时 → 所有设备并行发布 Release | ⚠️ 待实现矩阵 |
| **添加设备要简单** | 只需添加 `profiles/<device>/config`，不改 workflow | ✅ 已实现 |
| **零外部脚本** | 所有构建逻辑内联于 `build.yml`，不使用外部 shell 脚本 | ✅ 已实现 |
| **仅官方 Actions** | 仅使用 `actions/*` 官方包，Release/清理操作使用 `gh` CLI | ✅ 已实现 |
| **合理拆分步骤** | 构建流程分为多个阶段，步骤清晰 | ✅ 已实现 |
| **优化缓存** | 仅缓存 `dl/` + `.ccache`（CCACHE_DIR 显式设置），clone 后恢复 | ✅ 已实现 |

### 待实现功能

1. **矩阵构建**：`dev-build.yml` / `nightly-release.yml` 使用 `strategy.matrix` 并行构建多设备
2. **多源码配置**：支持在 workflow 中选择不同源码（如 OpenWrt 官方 vs ImmortalWrt）
3. **设备级插件差异**：允许 `profiles/<device>/packages.conf` 覆盖共享插件列表中的个别项
4. **Release 按设备分包**：不同设备的固件发布到同一 Release，按设备名区分

### 设计原则

- **Profile 为中心**：`profiles/<device>/` 是设备配置的唯一入口
- **源码无关**：源码参数通过 workflow input 传入，profile 不绑定源码
- **插件分层**：共享层 `configs/packages.conf` + 设备层 `profiles/<device>/config`
- **声明式配置**：尽量用 YAML 原生能力，不写脚本
- **仅官方 Actions**：仅使用 `actions/*` 官方包，Release/清理用 `gh` CLI

---

## 1. Architecture

All build logic lives in `.github/workflows/build.yml` as native GitHub Actions steps. **No external scripts, no third-party actions.**

Only official `actions/*` are used:
- `actions/checkout@v4` — repository checkout
- `actions/cache@v4` — dl/ and .ccache caching
- `actions/upload-artifact@v4` — firmware artifact upload

Release/清理操作使用 GitHub CLI (`gh`)，无需第三方 action。

The workflow is a reusable workflow (`workflow_call`) called by:
- `dev-build.yml` → push to `dev` → artifacts only
- `nightly-release.yml` → cron on `main` → GitHub Releases

### Build Phases

| Phase | Step | What Happens |
|-------|------|-------------|
| 1 | Checkout + Env | Set BUILD_DATE, ARTIFACT_NAME, RELEASE_TAG |
| 2 | Free disk | Remove dotnet, android, CodeQL, docker images |
| 3 | Install deps | apt-get install build dependencies inline |
| 4 | Clone source | `git clone --depth=1` into `/workdir/openwrt` |
| 5 | Restore cache | **After clone** — restore `dl/` and `.ccache` (with CCACHE_DIR) |
| 6 | Third-party feeds | Inline: profile-gated feed setup (ddnsto, mosdns, geodata, etc.) |
| 7 | Feeds update/install | `feeds update -a` → source-specific overrides → `feeds install -a -f` |
| 8 | Load config | Device config + shared packages.conf merge → `.config` |
| 9 | Download sources | `make defconfig && make download` |
| 10 | Compile | Parallel → single thread → verbose retry cascade |
| 11 | Collect & publish | Extract firmware, upload artifact / `gh release create` |

## 2. Cache Strategy

**Only two caches, restored AFTER clone (safe):**

| Cache | Path | Key | Purpose |
|-------|------|-----|---------|
| dl | `/workdir/openwrt/dl` | `dl-{profile}-{branch}` | Downloaded source tarballs |
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
2. `grep -v '^\s*#' configs/packages.conf | grep -v '^\s*$' >> .config` — 共享插件列表
3. `make defconfig` — resolve dependencies

**未来扩展**：允许 `profiles/<device>/packages.override` 增删个别插件

### Third-party feeds
Third-party feed setup is inlined in `build.yml` Phase 6, profile-gated. No hooks or scripts needed.

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
| `.github/workflows/nightly-release.yml` | Release 触发器 (cron on main) |
| `configs/packages.conf` | 共享插件列表（同源码下所有设备共用） |
| `profiles/*/config` | 设备硬件配置 |
| `profiles/*/files/` | 固件 overlay 文件 (可选) |

## 6. Common Pitfalls

- **Reusable Workflow Inputs**: Use `inputs.*` context, NOT `github.event.inputs.*`
- **Cache Before Clone**: NEVER restore cache before `git clone`. Always after.
- **Feed Override Order**: inline feed setup → feeds update → source-specific overrides → feeds install
- **BOM Encoding**: All files must be UTF-8 WITHOUT BOM
- **LF Line Endings**: Enforced via `.gitattributes`
- **CCACHE_DIR**: Must be set explicitly; OpenWrt doesn't default to `.ccache` in source root
- **Golang**: mosdns v5 needs Go 1.25+ → use `sbwml/packages_lang_golang` branch `25.x`
- **Action Versions**: Pin all `uses:` to specific tags (not `@master`/`@main`)

## 7. Adding New Devices

1. Create `profiles/<device>/config` with target, device, and `CONFIG_CCACHE=y`
2. Optionally add `files/` for custom overlay
3. Add profile-specific third-party feed logic in `build.yml` Phase 6 if needed
4. Update `dev-build.yml` / `nightly-release.yml` matrix to include new device

## 8. Debugging Failed Builds

- Check the **Compile firmware** step for the actual error
- The retry cascade provides verbose output: `make -j1 V=s`
- If `No space left on device` → check disk cleanup step
- If `golang` or `mosdns` build fails → check golang override ran after feeds update
- If `v2dat` fails with `go >= 1.25.0` → golang 25.x override didn't apply
- To debug interactively: add `tmate` SSH step to build.yml temporarily (not included by default to avoid third-party deps)
