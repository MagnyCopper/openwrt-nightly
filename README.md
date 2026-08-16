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
| main 每月两次定时 → Artifacts | ✅ 已实现 |
| 仅官方 Actions | ✅ 已实现 |

## 使用方法

### 自动构建

- **开发分支 (dev)**: 推送到 `profiles/`、`configs/` 或 workflow 文件时自动构建，产物保留 14 天
- **主分支 (main)**: 每月 2、16 号 04:00 HKT 自动构建，产物保留 14 天

### 手动触发

1. 进入 Actions 页面
2. 选择 **Dev Build** 或 **Biweekly Build** workflow
3. 点击 "Run workflow"，可选指定设备 profile

### 下载固件

构建完成后，在 Actions 页面对应的 workflow run 中下载 Artifacts（包含固件镜像、sha256sums、config.buildinfo 和 manifest）。

## 目录结构

```
configs/
  immortalwrt/          # 按固件源码分目录 (build.yml 按 source_name 读取对应子目录)
    packages.conf       # ImmortalWrt 共享插件清单 (基础镜像模式:未注释=生效,注释=暂缓待验证)

profiles/
  r2s/                   # NanoPi R2S
    config               # 硬件配置 (target, 分区, USB 网卡驱动)
    files/               # 自定义固件文件 (开机自动应用)
      etc/uci-defaults/
        80-packet-steering  # RPS 多核网络负载均衡
        99-custom-settings  # 首启设置 LAN IP 为 192.168.10.1 (避开上级路由 192.168.1.x)

.github/workflows/
  build.yml              # 可复用构建工作流 (核心引擎，仅官方 actions，零外部脚本)
  dev-build.yml          # dev 分支触发器
  biweekly-build.yml     # main 分支每月两次定时触发 (2、16 号 04:00 HKT)
```

## 已启用插件（ImmortalWrt）

基础镜像模式：`configs/immortalwrt/packages.conf` 中**未注释的行才会编入固件**，注释行为暂缓启用的候选插件（先在测试机验证，满意后取消注释并推 dev 即可启用，构建逻辑自动过滤 `#` 行）。除 ddnsto 外均为 ImmortalWrt 官方 feed 自带；ddnsto 的第三方源（linkease/nas-packages）已在 build.yml Feeds 阶段自动配置，当前已注释改用运行时脚本安装，feed 保留供未来重新启用。

### 生效中（9 项，随固件构建）

| 项 | 说明 |
|------|------|
| luci-app-openclash | 科学上网代理客户端 (Clash.Meta 内核) |
| luci-theme-argon | Argon 现代主题 |
| luci-app-argon-config | Argon 主题设置 |
| bash | 完整 Shell（OpenClash 脚本依赖）|
| nano | 友好文本编辑器 |
| htop | 交互式进程监控 |
| mtr-nojson | 路由追踪（轻量版）|
| tcpdump | 网络抓包（断网诊断刚需）|
| iperf3 | 内网测速 |

### 暂缓启用（20 项，已在 packages.conf 中注释）

| 项 | 暂缓原因 |
|------|------|
| luci-app-smartdns | DNS 加速，待试验田验证 |
| luci-app-adblock | 与 openclash reject 规则重叠，待验证 |
| luci-app-attendedsysupgrade | 仅适用官方 ASU 服务器，自编译固件用不上 |
| luci-app-ttyd | 已有 SSH，按需启用 |
| luci-app-ramfree | Linux 内存管理自足，收益存疑 |
| luci-app-watchcat | 日志实证 5 天零重启，待验证 |
| luci-app-autoreboot | 与 watchcat 功能重叠 |
| luci-app-netdata | 实时监控，待验证 |
| luci-app-nlbwmon | 流量记账，待验证 |
| luci-app-upnp | 日志显示仅失效订阅刷屏，场景存疑 |
| luci-app-irqbalance | 双核收益边际 |
| luci-app-arpbind | 内网无 ARP 欺骗史 |
| luci-app-sqm | R2S 跑不动千兆 CAKE，低带宽才考虑 |
| luci-app-appfilter | 家庭管控场景，待验证 |
| luci-app-zerotier | 大陆裸连不稳 |
| luci-app-nps | 需自备 VPS |
| ddnsto + luci-app-ddnsto | 改用 koolcenter 脚本按需安装（每次固件升级后需重跑）|
| luci-app-wol | 无远程开机需求 |
| luci-app-wechatpush | 通知推送，待验证 |

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

**3. 第三方软件源（当前无需）**

当前 ImmortalWrt 构建的插件全部自带于 ImmortalWrt 官方 feed，无需任何第三方源。若未来某设备/源码确实需要，参考下文“添加第三方软件源”的三种方式，在 `build.yml` 的 Feeds 阶段添加。

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
- 不同源码的默认 feeds 和软件包不同，切换源码时需在 `configs/<source_name>/packages.conf` 提供对应清单（缺失会在构建时报错中止）
- 当前 ImmortalWrt 的插件全部自带；其他源码可能需要第三方软件源（在 `build.yml` Feeds 阶段按需添加）
- 首次使用新源码建议先手动触发测试，确认构建通过后再用于定时构建

### 添加第三方软件源

第三方软件源配置直接内联于 `build.yml` 的 Feeds 阶段。当前 ImmortalWrt 构建无需第三方源（全部自带）；如未来需要，支持三种方式：

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

- 默认地址: http://192.168.10.1 或 http://immortalwrt.lan（uci-defaults 首启自动设置，上级网络为 192.168.1.x）
- 用户名: root
- 密码: 无
