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
