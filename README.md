# openwrt-nightly

openwrt的每日自动构建打包发布

## 主要步骤

1. 安装编译OpenWRT所依赖的环境软件;
2. 修改源码中feeds配置,添加定制化的插件源;
3. 修改源码中路由器IP地址;
4. 更新并安装feeds文件;
5. 按给定的配置文件生成默认编译配置;
6. 下载相关依赖文件;
7. 编译OpenWRT固件;
8. 上传编译结果文件;

## 插件清单

- luci-theme-argon-18.06
- luci-app-argon-config
- luci-app-attendedsysupgrade
- luci-app-ddnsto
- luci-app-design-config
- luci-app-netdata
- luci-app-nft-qos
- luci-app-ramfree
- luci-app-serverchan
- luci-app-smartdns
- luci-app-ttyd
- luci-app-uugamebooster
- luci-app-vssr
- luci-app-watchcat
- luci-app-wrtbwmon