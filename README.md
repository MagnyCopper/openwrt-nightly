# OpenWrt Nightly Build

基于 GitHub Actions 的 ImmortalWrt 固件自动构建系统（当前仅 NanoPi R2S）。架构设计支持未来扩展为多源码、多设备。

## 当前状态

| 功能 | 状态 |
|------|------|
| ImmortalWrt + R2S 构建 | ✅ 已验证 |
| 多源码切换（workflow input） | ✅ 架构就绪，仅 ImmortalWrt 已验证 |
| 多设备支持（profile 系统） | ✅ 架构就绪，仅 R2S 已实现 |
| 并行矩阵构建 | ⚠️ 待实现 |
| dev 推送 → Artifacts | ✅ 已实现 |
| main 双周定时 → Artifacts | ✅ 已实现 |
| 仅官方 Actions | ✅ 已实现 |

## 使用方法

### 自动构建

- **开发分支 (dev)**: 推送到 `profiles/`、`configs/` 或 workflow 文件时自动构建，产物保留 14 天
- **主分支 (main)**: 每 2 周自动构建，产物保留 14 天

### 手动触发

1. 进入 Actions 页面
2. 选择 **Dev Build** 或 **Biweekly Build** workflow
3. 点击 "Run workflow"，可选指定设备 profile

### 下载固件

构建完成后，在 Actions 页面对应的 workflow run 中下载 Artifacts（包含固件镜像、sha256sums、config.buildinfo 和 manifest）。

## 目录结构

```
configs/
  packages.conf          # 共享插件列表

profiles/
  r2s/                   # NanoPi R2S
    config               # 硬件配置 (target, 分区, USB 网卡驱动)
    files/               # 自定义固件文件 (开机自动应用)
      etc/uci-defaults/
        80-packet-steering  # RPS 多核网络负载均衡

.github/workflows/
  build.yml              # 可复用构建工作流 (核心引擎，仅官方 actions，零外部脚本)
  dev-build.yml          # dev 分支触发器
  biweekly-build.yml     # main 分支双周定时触发
```

## 已启用插件（ImmortalWrt R2S）

### 主题

| 插件 | 说明 |
|------|------|
| luci-theme-argon | Argon 现代主题 |
| luci-app-argon-config | Argon 主题设置 |

### VPN & 代理

| 插件 | 说明 |
|------|------|
| luci-app-openclash | 科学上网代理客户端 (Clash.Meta 内核) |
| tailscale | 零配置 WireGuard VPN 组网 |

### DNS

| 插件 | 说明 |
|------|------|
| luci-app-mosdns | DNS 分流插件 (配合 OpenClash 使用) |

### 远程访问

| 插件 | 说明 |
|------|------|
| ddnsto + luci-app-ddnsto | 内网穿透 (无需公网 IP) |

### 网络

| 插件 | 说明 |
|------|------|
| luci-app-upnp | 自动端口映射 |
| luci-app-nft-qos | 实时流量限制 |
| luci-app-nlbwmon | 带宽监控统计 |

### 系统管理

| 插件 | 说明 |
|------|------|
| luci-app-watchcat | 定时重启 / 网络监测重启 |
| luci-app-netdata | 实时系统资源监控 |
| luci-app-attendedsysupgrade | 在线固件升级 |
| luci-app-irqbalance | IRQ 中断负载均衡 |
| luci-app-ramfree | 内存释放 |
| luci-app-statistics | 历史资源统计图表 |

### 设备管理

| 插件 | 说明 |
|------|------|
| luci-app-arpbind | IP/MAC 地址绑定 |
| luci-app-wol | 网络唤醒 |
| luci-app-appfilter | 应用过滤 (上网管控) |

### 工具

| 插件 | 说明 |
|------|------|
| luci-app-ttyd | Web 终端 |
| htop | 交互式进程查看器 |
| wget-ssl / curl | 下载工具 |
| iperf3 | 网络性能测试 |
| tcpdump | 网络抓包 |

### 可选插件 (取消注释启用)

AdGuard Home, DDNS-Go, Samba4, FRP, WeChatPush, ZeroTier

## 性能优化

### Packet Steering (RPS)

R2S 的 4 核 Cortex-A53 在默认配置下，所有网络中断都由 CPU0 处理。本固件启用两级优化：

1. **IRQ Affinity** (ImmortalWrt 内置): `eth0→CPU1`, `eth1→CPU2`
2. **Packet Steering** (uci-defaults): `packet_steering=2`，将接收数据包分发到所有 CPU 核心处理

### 构建优化

- 仅使用官方 `actions/*` 包（checkout、cache、upload-artifact），清理使用 GitHub CLI (`gh`)
- 仅缓存 `dl/`（源码包）和 `.ccache`（编译缓存），避免工具链缓存与新源码不兼容
- 三级重试: 并行编译 → 单线程 → 详细单线程日志
- 自动清理 Runner 磁盘空间
- 所有构建逻辑内联于 `build.yml`，零外部脚本依赖
- 构建产物包含 `config.buildinfo` 和 `manifest`，便于审计

## 扩展指南

### 添加新设备

以添加 NanoPi R4S 为例：

**1. 创建设备配置** `profiles/r4s/config`

```ini
CONFIG_TARGET_rockchip=y
CONFIG_TARGET_rockchip_armv8=y
CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-r4s=y
CONFIG_CCACHE=y
```

> `CONFIG_CCACHE=y` 是必选项。其余配置参考对应源码的 `make menuconfig` 输出。

**2.（可选）添加自定义固件文件**

```
profiles/r4s/files/
  etc/uci-defaults/
    99-custom-settings    # 首次启动自动执行的 uci 脚本
```

**3.（可选）添加设备专属第三方软件源**

在 `build.yml` 的 "Setup third-party feeds" 步骤中添加 profile 条件：

```yaml
if [ "$PROFILE" = "r4s" ]; then
  echo "src-git feedname https://github.com/user/repo.git" >> feeds.conf.default
fi
```

**4. 手动触发测试**

```bash
gh workflow run dev-build.yml --ref dev -f profile=r4s
```

**5.（未来）加入矩阵构建**

待矩阵构建实现后，在 `dev-build.yml` / `biweekly-build.yml` 的 matrix 中添加 `r4s` 即可自动构建。

### 切换/添加源码

`build.yml` 通过 workflow inputs 实现源码无关设计，**无需修改 `build.yml` 本身**。只需在调用时传入不同参数。

**手动指定源码触发构建：**

```bash
# OpenWrt 官方源码
gh workflow run dev-build.yml --ref dev \
  -f source_repo_url='https://github.com/openwrt/openwrt.git' \
  -f source_branch='v24.10.x' \
  -f source_name='openwrt'

# 其他 fork
gh workflow run dev-build.yml --ref dev \
  -f source_repo_url='https://github.com/username/custom-openwrt.git' \
  -f source_branch='main' \
  -f source_name='custom'
```

**注意事项：**
- 不同源码的默认 feeds 和软件包不同，`packages.conf` 中的插件可能需要调整
- 不同源码可能需要不同的第三方软件源逻辑（在 `build.yml` Phase 6 中按 profile 或 source_name 条件添加）
- 首次使用新源码建议先手动触发测试，确认构建通过后再用于定时构建

### 添加第三方软件源

第三方软件源配置直接内联于 `build.yml` Phase 6，按 profile 条件执行。支持三种方式：

**方式一：添加为正式 feed（推荐）**

适用于包含多个软件包的源，依赖关系由 feed 系统自动处理：

```yaml
echo "src-git feedname https://github.com/user/repo.git;branch" >> feeds.conf.default
# 在 feeds install 阶段安装
./scripts/feeds install -f -p feedname package_name
```

**方式二：clone 到 package/ 目录**

适用于独立的数据文件包或不需要 feed 依赖解析的简单包：

```yaml
git clone --depth=1 https://github.com/user/repo.git package/repo-name
```

**方式三：覆盖已有 feed 中的包**

适用于需要用自定义版本替换源码自带包的场景（如 golang 工具链升级）：

```yaml
rm -rf feeds/packages/lang/golang
git clone --depth=1 -b 25.x https://github.com/user/golang.git feeds/packages/lang/golang
./scripts/feeds update -i packages
./scripts/feeds install -f -p packages golang
```

## 固件信息

- 默认地址: http://192.168.1.1 或 http://immortalwrt.lan
- 用户名: root
- 密码: 无
