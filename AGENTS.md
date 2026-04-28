# AGENTS.md - OpenWrt Nightly Build Project

## 1. Architecture

All build logic lives in `.github/workflows/build.yml` as native GitHub Actions steps. **No external scripts are used — zero scripts.**

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
| 6 | Third-party feeds | Inline: ddnsto feeds, mosdns/geodata clones, golang override flag |
| 7 | Feeds update/install | `feeds update -a` → golang 25.x override → `feeds install -a -f` |
| 8 | Load config | Device config + packages.conf merge → `.config` |
| 9 | Download sources | `make defconfig && make download` |
| 10 | Compile | Parallel → single thread → verbose retry cascade |
| 11 | Collect & publish | Extract firmware, upload artifact / release |

## 2. Cache Strategy

**Only two caches, restored AFTER clone (safe):**

| Cache | Path | Key | Purpose |
|-------|------|-----|---------|
| dl | `/workdir/openwrt/dl` | `dl-{profile}-{branch}` | Downloaded source tarballs |
| ccache | `/workdir/openwrt/.ccache` | `ccache-{profile}-{branch}-{config_hash}` | Compilation cache |

**CCACHE_DIR is explicitly set** to `/workdir/openwrt/.ccache` before compilation to ensure the cache directory matches the `actions/cache` path.

**Why NO toolchain cache:**
- ImmortalWrt uses `--depth=1` on `openwrt-24.10` branch → new HEAD each build
- Toolchain intermediate files from old source cause `off64_t` errors
- ccache handles source changes gracefully without corruption risk

**Requirement:** `CONFIG_CCACHE=y` must be in the device config.

## 3. Profile System

```
profiles/<name>/
  config              # Device hardware config + CONFIG_CCACHE=y
  files/              # Custom firmware files overlay (optional)
```

### Third-party feeds
Third-party feed setup is inlined in `build.yml` Phase 6, profile-gated. No hooks or scripts needed.

### Config Merging
1. `cp profiles/<profile>/config .config`
2. `grep -v '^\s*#' configs/packages.conf | grep -v '^\s*$' >> .config`
3. `make defconfig`

## 4. Source Configuration

Source parameters are workflow inputs:

```yaml
with:
  source_repo_url: 'https://github.com/immortalwrt/immortalwrt.git'
  source_branch: 'openwrt-24.10'
  source_name: 'immortalwrt'
```

## 5. Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/build.yml` | **Everything.** The sole build engine. Zero scripts. |
| `.github/workflows/dev-build.yml` | Dev trigger (push to dev) |
| `.github/workflows/nightly-release.yml` | Weekly release (cron on main) |
| `configs/packages.conf` | Shared package list (all profiles) |
| `profiles/*/config` | Device hardware config |
| `profiles/*/files/` | Firmware overlay files (optional) |

## 6. Common Pitfalls

- **Reusable Workflow Inputs**: Use `inputs.*` context, NOT `github.event.inputs.*`
- **Cache Before Clone**: NEVER restore cache before `git clone`. Always after.
- **Feed Override Order**: inline feed setup → feeds update → golang override → feeds install
- **BOM Encoding**: All files must be UTF-8 WITHOUT BOM
- **LF Line Endings**: Enforced via `.gitattributes`
- **CCACHE_DIR**: Must be set explicitly; OpenWrt doesn't default to `.ccache` in source root
- **Golang**: mosdns v5 needs Go 1.25+ → use sbwml/packages_lang_golang branch 25.x

## 7. Adding New Devices

1. Create `profiles/<device>/config` with target, device, and `CONFIG_CCACHE=y`
2. Optionally add `files/` for custom overlay
3. Add profile-specific third-party feed logic in `build.yml` Phase 6 if needed
4. Update dev-build.yml and nightly-release.yml defaults if needed

## 8. Debugging Failed Builds

- Check the **Compile firmware** step for the actual error
- The retry cascade provides verbose output: `make -j1 V=s`
- If `No space left on device` → check disk cleanup step
- If `golang` or `mosdns` build fails → check golang override ran after feeds update
- If `v2dat` fails with `go >= 1.25.0` → golang 25.x override didn't apply
- Use `ssh_debug: true` for interactive tmate session on the runner
