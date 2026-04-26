# OpenWrt Nightly Build

自动构建 ImmortalWrt 固件的 GitHub Actions CI/CD 系统。

## 支持设备

| 设备 | 状态 |
|------|------|
| NanoPi R2S | ✅ 已支持 |

## 支持源码

| 源码 | 状态 |
|------|------|
| ImmortalWrt | ✅ 已支持 |

## 使用方法

### 自动构建

- **主分支 (main)**: 每周日自动构建并发布到 [Releases](../../releases)
- **开发分支 (dev)**: 推送到 dev 分支时自动构建（仅 Artifacts）

### 手动触发

1. 进入 Actions 页面
2. 选择对应的 workflow
3. 点击 "Run workflow"

## 目录结构

```
profiles/          # 设备配置（每个设备一个目录）
└── r2s/
    ├── config     # .config 文件
    ├── files/     # 自定义固件文件
    └── hooks/     # 构建钩子脚本

scripts/           # 构建脚本
```

## 添加新设备

1. 创建 `profiles/<device>/config`（.config 文件）
2. 可选：添加 `profiles/<device>/files/` 和 `profiles/<device>/hooks/`
3. 在 workflow 中指定新的 profile 名称

## 添加新源码

1. 创建 `scripts/source-<name>.sh`
2. 定义 `SOURCE_REPO_URL`、`SOURCE_REPO_BRANCH`、`SOURCE_BUILD_DEPS`
3. 在 workflow 调用时传入 `source: source-<name>.sh`

## 固件信息

- 默认地址: http://192.168.1.1 或 http://immortalwrt.lan
- 用户名: root
- 密码: 无
