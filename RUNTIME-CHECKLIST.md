# 刷机后运行时手动清单（Runtime Checklist）

> 本镜像**刻意不包含**以下内容：UU 加速器插件、UU/OpenClash 共存补丁、Tailscale 登录认证、
> ddnsto 运行安装。原因见各节说明（账号绑定 / 运行时机制 / 需人工认证）。
>
> 排障全档案：`~/projects/immortalwrt-r2s/firmware-archive/2026-10-07-uu-openclash-coexistence.md`

---

## 方式 A：保留配置升级（sysupgrade，不勾选"不保留配置"）

overlay 分区整体保留，**绝大多数内容自动延续**：

| 项目 | 状态 |
|---|---|
| 自定义脚本（GRO/RPS/sysctl/LAN IP/fw4 zone/OpenClash 绕过） | ✅ 自动保留 |
| Tailscale 认证与子网广播 | ✅ 官方 `keep.d` 保留 `/etc/tailscale/`，且 `tailscale-tune` 开机自动对齐 |
| UU 插件本体（`/usr/sbin/uu`）与开机项 | ✅ 位于 overlay，自动保留 |
| OpenClash 主配置（gist 订阅源、custom 清单、标记放行规则） | ✅ 位于 overlay，自动保留 |

**需手动（通常仅 1 项）**：
1. OpenClash 启动后做一次**订阅更新**（GUI「配置订阅→更新」或等 03:00 cron），确认规则版本与 gist 一致；
2. 若 UU 会话异常：UU App 内关闭再开启一次加速（强制重建隧道，无需重装）。

---

## 方式 B：全新刷入 / 恢复出厂

首启自动完成：LAN IP(192.168.10.1)、fw4 tailscale zone 与 LAN 转发、OpenClash 100.64.0.0/10
绕过、GRO/RPS/sysctl 调优、`tailscale-tune` 服务（已 enable）。

**按顺序手动执行**：

### 1. 基础安全
```sh
passwd                      # 设置 root 密码（镜像默认无密码）
```

### 2. OpenClash
1. GUI 填入 gist 上游订阅 → 更新 → 启动；
2. **补 UU 虚拟网段放行**（UU 共存的官方通道）——编辑
   `/etc/openclash/custom/openclash_custom_localnetwork_ipv4.list`，追加 5 段：
   ```
   163.163.0.0/18
   163.163.127.0
   163.163.127.162
   163.163.163.255
   163.163.192.0/18
   ```
3. **补标记放行规则**（OpenClash「自定义防火墙规则」），防止 clash 抢走已标记游戏 UDP：
   ```
   nft insert rule inet fw4 openclash_mangle ip daddr != 198.18.0.0/16 meta mark 0x163 counter return comment "UU-mark-bypass-163"
   nft insert rule inet fw4 openclash_mangle ip daddr != 198.18.0.0/16 meta mark 0x164 counter return comment "UU-mark-bypass-164"
   ```
4. 重启 OpenClash 生效。

### 3. UU 加速器
```sh
# 官方一键脚本重装；sn 绑定基于路由器 MAC，同机重装无缝重绑
wget -O /tmp/install.sh https://uu.gdl.netease.com/.../install.sh && sh /tmp/install.sh
```
装完在 UU App 重新绑定设备。**装机后检查项**：
- `nft list table inet uu_dns_guard` 存在（DNS 保护闸，UDP/53 按标记押回本机）；
  若缺失，按上方档案文档重建；
- Xbox 实测一局：`openclash_mangle` 中 `UU-mark-bypass-163/164` 计数增长、clash 拦截为 0。

### 4. Tailscale
1. `tailscale up`（或等 `tailscale-tune` 已自动广播），浏览器打开认证 URL 登录；
2. 管理台批准 `192.168.10.0/24` 子网路由；**关闭 key expiry**（防异地掉线重认证）；
3. 蜂窝网络端到端验证：访问 `http://192.168.10.1` + 一台内网设备。

### 5. ddnsto（可选，按需）
```sh
# koolcenter 脚本按需安装（packages.conf 已注明刻意不进固件）
```

---

## 与固件无关的常设项（不在路由器上）

- **Tailscale 管理台**：key expiry 已关闭（控制台设置，随账号持久）；
- **iOS Shadowrocket**：`IP-CIDR,192.168.10.0/24,TAILSCALE,no-resolve` 规则 +
  TUN 排除项仅保留 `192.168.0.0/24`（客户端侧配置，gist：lazy_group）；
- **UU App**：设备绑定关系在账号侧。

---

## 为什么这些不进固件

| 项 | 原因 |
|---|---|
| UU 插件 | 账号绑定 + 官方脚本运行时装机制，同 MAC 重装无缝重绑 |
| UU/OpenClash 共存补丁 | 依赖 OpenClash 运行状态与订阅顺序，属运行时机制 |
| Tailscale 登录 | 必须人工浏览器认证，无法预置 |
| ddnsto | 刻意 staged（packages.conf 注明） |
