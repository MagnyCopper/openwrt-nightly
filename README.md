# OpenWrt Nightly Build

基于 GitHub Actions 的 ImmortalWrt 固件自动构建系统，专为 NanoPi R2S 优化。

## 支持设备

| 设备 | SoC | 架构 | 状态 |
|------|-----|------|------|
| NanoPi R2S | RK3328 | rockchip/armv8 | ✅ 已支持 |

## 使用方法

### 自动构建

- **主分支 (main)**: 每周日自动构建并发布到 [Releases](../../releases)
- **开发分支 (dev)**: 推送到 `profiles/`、`configs/` 或 workflow 文件时自动构建（仅 Artifacts）

### 手动触发

1. 进入 Actions 页面
2. 选择 **Dev Build** 或 **Nightly Release** workflow
3. 点击 "Run workflow"

## 目录结构

```
configs/
  packages.conf          # 所有设备共享的插件列表

profiles/
  r2s/
    config               # R2S 硬件配置 (target, 分区, USB 网卡驱动)
    files/                # 自定义固件文件 (开机自动应用)
      etc/uci-defaults/
        80-packet-steering  # RPS 多核网络负载均衡

.github/workflows/
  build.yml              # 可复用构建工作流 (核心引擎，无外部脚本)
  dev-build.yml          # dev 分支触发器
  nightly-release.yml    # main 分支定时发布
```

## 已启用插件

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

- 仅缓存 `dl/`（源码包）和 `.ccache`（编译缓存），避免工具链缓存与新源码不兼容
- 三级重试: 并行编译 → 单线程 → 详细单线程日志
- 自动清理 Runner 磁盘空间
- 所有构建逻辑内联于 `build.yml`，无外部脚本依赖

## 添加新设备

1. 创建 `profiles/<device>/config` — 硬件配置（须包含 `CONFIG_CCACHE=y`）
2. 可选: 添加 `files/` (自定义固件文件)
3. 在 `build.yml` Phase 6 中添加设备专属的第三方软件源逻辑
4. 更新 `dev-build.yml` 和 `nightly-release.yml` 的默认 profile

## 添加第三方软件源

第三方软件源配置直接内联于 `build.yml` 的 Phase 6 步骤中，按 profile 条件执行：

```yaml
- name: Setup third-party feeds
  run: |
    if [ "$PROFILE" = "your-device" ]; then
      # 方式一: 添加 feed 源
      echo "src-git feedname https://github.com/user/repo.git" >> feeds.conf.default
      # 方式二: 直接克隆到 package 目录
      git clone --depth=1 https://github.com/user/repo.git package/repo-name
    fi
```

## 固件信息

- 默认地址: http://192.168.1.1 或 http://immortalwrt.lan
- 用户名: root
- 密码: 无
