# AGENTS.md - OpenWrt Nightly Build Project

## 1. Architecture

All build logic lives in `.github/workflows/build.yml` as native GitHub Actions steps. **No external scripts are used.**

The workflow is a reusable workflow (`workflow_call`) called by:
- `dev-build.yml` → push to `dev` → artifacts only
- `nightly-release.yml` → cron on `main` → GitHub Releases

### Build Phases

| Phase | Step | What Happens |
|-------|------|-------------|
| 1 | Checkout + Env | Set BUILD_DATE, ARTIFACT_NAME, RELEASE_TAG as env vars |
| 2 | Free disk | Remove dotnet, android, CodeQL, docker images |
| 3 | Install deps | apt-get install build dependencies inline |
| 4 | Clone source | `git clone --depth=1` into `/workdir/openwrt` |
| 5 | Restore cache | **After clone** — restore `dl/` and `.ccache` only |
| 6 | Third-party feeds | Source `profiles/<profile>/hooks/pre-build.sh` |
| 7 | Feeds update/install | `feeds update -a` → golang override if needed → `feeds install -a -f` |
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

**Why NO toolchain cache:**
- ImmortalWrt uses `--depth=1` on `openwrt-24.10` branch → new HEAD each build
- Toolchain intermediate files from old source cause `off64_t` errors
- ccache handles source changes gracefully without corruption risk

**Requirement:** `CONFIG_CCACHE=y` must be in the device config.

## 3. Profile System

```
profiles/<name>/
  config              # Device hardware config + CONFIG_CCACHE=y
  hooks/pre-build.sh  # Third-party feed setup (optional)
  files/              # Custom firmware files overlay
```

### pre-build.sh (only if needed)
Runs in `/workdir/openwrt` context. Used to:
- Add third-party feed entries to `feeds.conf.default`
- Clone packages into `package/` dir (overrides feed version)
- Signal golang toolchain override via `/tmp/.golang-override`

### Config Merging
1. `cp profiles/<profile>/config .config`
2. `grep -v '^\s*#' configs/packages.conf | grep -v '^\s*$' >> .config`
3. `make defconfig`

## 4. Source Configuration

Source parameters are workflow inputs, not scripts:

```yaml
with:
  source_repo_url: 'https://github.com/immortalwrt/immortalwrt.git'
  source_branch: 'openwrt-24.10'
  source_name: 'immortalwrt'
```

## 5. Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/build.yml` | **Everything.** The sole build engine. No scripts needed. |
| `.github/workflows/dev-build.yml` | Dev trigger (push to dev) |
| `.github/workflows/nightly-release.yml` | Weekly release (cron on main) |
| `configs/packages.conf` | Shared package list (all profiles) |
| `profiles/*/config` | Device hardware config |
| `profiles/*/hooks/pre-build.sh` | Third-party feed setup (optional) |
| `profiles/*/files/` | Firmware overlay files |

## 6. Common Pitfalls

- **Reusable Workflow Inputs**: Use `inputs.*` context, NOT `github.event.inputs.*`
- **Cache Before Clone**: NEVER restore cache before `git clone`. Always after.
- **Feed Override Order**: pre-build hook → feeds update → golang override → feeds install
- **BOM Encoding**: All files must be UTF-8 WITHOUT BOM
- **LF Line Endings**: Enforced via `.gitattributes`
- **Package Override**: Clone into `package/` dir to override feed version; use `feeds install -a -f`

## 7. Adding New Devices

1. Create `profiles/<device>/config` with target, device, and `CONFIG_CCACHE=y`
2. Optionally add `hooks/pre-build.sh` for third-party feeds
3. Optionally add `files/` for custom overlay
4. Update dev-build.yml and nightly-release.yml defaults if needed

## 8. Debugging Failed Builds

- Check the **Compile firmware** step for the actual error
- The retry cascade provides verbose output: `make -j1 V=s`
- If `No space left on device` → check disk cleanup step
- If `golang` or `mosdns` build fails → check golang override ran after feeds update
- Use `ssh_debug: true` for interactive tmate session on the runner
