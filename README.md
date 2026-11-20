# XG040MD OpenWrt 固件编译仓库

基于 [ztb666ai/Actions-OpenWrt-AN758X](https://github.com/ztb666ai/Actions-OpenWrt-AN758X) 和 [ponwrt](https://github.com/pbs05/ponwrt) 构建，专为 **Nokia XG-040G-MD (UBI)** 定制的 OpenWrt 固件编译项目。

## 📦 硬件规格

| 项目 | 规格 |
|------|------|
| **芯片组** | Airoha AN7581 |
| **存储** | UBI (NAND) |
| **网口** | 2.5G × 1 (EN8811H PHY) |
| **USB** | USB 3.0 × 2 (5V 供电可控) |
| **无线** | 无内置无线，支持 USB 无线网卡扩展 |
| **光模块** | Airoha EN7572 (BOSA/RI 校准) |

## 🎯 预置功能

### 核心功能
- ✅ **PON 拨号支持** - OMCI/OAM 协议完整支持，LOID 认证
- ✅ **硬件 NAT 加速** - PPE/HNAT 全开启，2.5G 线速转发
- ✅ **IPTV 桥接** - VLAN 绑定、组播转发
- ✅ **光模块监控** - DDM 光功率/温度/偏置电流实时查看

### 扩展功能（本仓库额外添加）
- 📡 **USB 无线驱动全家桶** - 支持主流 USB WiFi 芯片：
  - Realtek: 8811CU, 88x2bu, 8812au, 8821cu, 8814au, 8723bu, 8192eu
  - MediaTek: mt76x2u, MT7921U
- ⏰ **定时重启** - `luci-app-autoreboot` (每天凌晨 4 点自动重启)
- 🕐 **NTP 服务器** - 预配置国内优质 NTP 源：
  - `ntp.ntsc.ac.cn` (中国科学院国家授时中心)
  - `ntp1.aliyun.com` (阿里云)
  - `cn.pool.ntp.org` (NTP 池)
  - `time.cloudflare.com` (Cloudflare)
- 🖥️ **ttyd Web 终端** - 浏览器直接访问 Shell，端口 7681
- 🎨 **Argon 主题** - 现代化 LuCI 界面

### 代理插件（可选）
- OpenClash (默认)
- DAE
- Honk

## 🚀 快速开始

### 1. Fork 仓库
点击右上角 **Fork** 到你的 GitHub 账号

### 2. 启用 Actions
进入仓库 **Settings → Actions → General**，选择：
- ✅ Allow all actions and reusable workflows
- ✅ Allow GitHub Actions to create and approve pull requests

### 3. 触发编译
进入 **Actions → Build PonWrt for XG040MD → Run workflow**，配置：

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `profile` | `nokia_xg-040g-md-ubi` | 固定，XG040MD UBI 版 |
| `proxy` | `openclash` | 代理插件：openclash/dae/honk/留空 |
| `disable_packages` | 默认即可 | 要禁用的包，空格分隔 |
| `fw_author` | 你的 GitHub ID | 显示在固件版本里 |
| `upload_release` | `true` | 编译完成自动发布 Release |
| `ignore_cache` | `false` | 首次编译建议 false，重编可开 true |

点击 **Run workflow** 等待 1-2 小时

### 4. 获取固件
- **Artifacts**: Actions 运行页面下载（保留 30 天）
- **Releases**: 仓库 Releases 页面下载（永久保留）

## 📁 固件文件说明

编译产出的主要文件：
```
ponwrt-an7581-nokia_xg-040g-md-ubi-<版本>.itb    # FIT 镜像，用于 Web 升级/TTL 刷机
ponwrt-an7581-nokia_xg-040g-md-ubi-<版本>.ubi   # UBI 镜像，用于 TTL/编程器刷机
```

## 🔧 刷机指南

### Web 升级 (推荐)
1. 登录原厂/现有 OpenWrt Web 界面
2. 系统 → 备份/升级 → 刷写新固件
3. 选择 `.itb` 文件，**取消勾选** "保留配置"
4. 等待重启完成

### TTL 救砖
```bash
# U-Boot 下
tftpboot 0x44000000 ponwrt-an7581-nokia_xg-040g-md-ubi-xxx.ubi
nand erase.part rootfs
nand write 0x44000000 0x$(nand info | grep rootfs | awk '{print $2}') ${filesize}
reset
```

⚠️ **注意**：首次从原厂固件刷入建议使用 TTL，Web 升级有变砖风险

## ⚙️ 默认配置

| 项目 | 值 |
|------|-----|
| **管理地址** | http://192.168.2.1 |
| **用户名** | root |
| **密码** | 无（首次登录自行设置） |
| **WiFi** | 无内置，插入 USB 网卡后自动检测 |
| **ttyd 终端** | http://192.168.2.1:7681 |
| **时区** | Asia/Shanghai (CST-8) |
| **NTP 服务器** | 4 个国内优质源 |

## 📂 仓库结构

```
.
├── .github/workflows/build.yml    # GitHub Actions 编译流程
├── configs/
│   └── nokia_xg-040g-md-ubi.config  # 机型精简配置
├── diy-part1.sh                   # 插件拉取脚本
├── diy-part2.sh                   # 定制配置脚本
├── files/                         # 根文件系统覆盖层
│   ├── etc/
│   │   ├── uci-defaults/          # 首次启动初始化脚本
│   │   ├── hotplug.d/             # 热插拔脚本
│   │   └── sysctl.conf            # 内核参数调优
│   ├── usr/bin/mount-opt          # USB 自动挂载工具
│   └── sbin/                      # 系统工具
└── README.md
```

## 🛠️ 自定义编译

### 添加/删除软件包
修改 `configs/nokia_xg-040g-md-ubi.config`：
```bash
# 添加包
CONFIG_PACKAGE_<包名>=y

# 删除包
# CONFIG_PACKAGE_<包名> is not set
```

### 修改默认设置
编辑 `diy-part2.sh` 中的参数：
```bash
LAN_IP="192.168.x.x"           # 修改 LAN IP
LAN_HOSTNAME="MyRouter"        # 修改主机名
PROXY_VARIANT="dae"            # 切换代理插件
```

### 添加自定义文件
将文件放入 `files/` 目录对应路径，编译时会自动覆盖到固件

## 🙏 致谢

- [pbs05/ponwrt](https://github.com/pbs05/ponwrt) - 上游源码
- [ztb666ai/Actions-OpenWrt-AN758X](https://github.com/ztb666ai/Actions-OpenWrt-AN758X) - CI 模板
- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) - 基础固件
- [Airoha](https://www.airoha.com/) - SoC 厂商 SDK
- 所有开源驱动作者

## 📄 许可证

遵循上游项目许可证 (GPL-2.0 / GPL-3.0 / MIT 等)

---

> ⚡ **提示**：编译耗时较长（首次约 2-3 小时，后续缓存约 40 分钟），建议先 Fork 后耐心等待。如遇编译失败，请查看 Actions 日志排查，常见原因：上游源码变动、包依赖冲突、磁盘空间不足。