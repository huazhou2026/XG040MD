#!/bin/bash
# ================================================================
# diy-part2.sh —— 默认值定制（.config 加载之后、defconfig 之前运行）
# 功能清单：
# [7.7] USB 自动挂载到 /opt（mount-opt + hotplug + uci-defaults）
# [7.9] /etc/sysctl.conf 内核调优
# [10] 默认 LAN IP=192.168.2.1、hostname=XG040MD、时区 Asia/Shanghai
# [10.5] uci-defaults 强制中国时区（保配置升级也生效）
# [10.6] NTP 服务器配置
# [10.7] ttyd Web 终端配置
# [11] 代理插件注入
# [12] 自定义包开关
# ================================================================
set -euo pipefail

# ---- 可调参数（均有默认值，可用环境变量覆盖，不必改代码）----
LAN_IP="${LAN_IP:-192.168.2.1}"
LAN_HOSTNAME="${LAN_HOSTNAME:-XG040MD}"
ENABLE_USB_OPT_MOUNT="${ENABLE_USB_OPT_MOUNT:-1}"
ENABLE_SYSCTL_TUNING="${ENABLE_SYSCTL_TUNING:-1}"
DISABLE_PACKAGES="${DISABLE_PACKAGES:-}"
PROXY_VARIANT="${PROXY_VARIANT:-openclash}"

echo "=========================================="
echo "默认值定制 (diy-part2.sh)"
echo " LAN_IP = ${LAN_IP}"
echo " LAN_HOSTNAME = ${LAN_HOSTNAME}"
echo " USB /opt = ${ENABLE_USB_OPT_MOUNT}"
echo " sysctl 调优 = ${ENABLE_SYSCTL_TUNING}"
echo " 代理插件 = ${PROXY_VARIANT}"
echo "=========================================="

# ================================================================
# [7.7] USB 自动挂载到 /opt
# ================================================================
if [ "${ENABLE_USB_OPT_MOUNT}" = "1" ]; then
  mkdir -p files/usr/bin files/etc/hotplug.d/block files/etc/uci-defaults

  cat > files/usr/bin/mount-opt <<'EOF'
#!/bin/sh
MOUNT_POINT="/opt"
do_mount() {
  local dev
  mkdir -p "$MOUNT_POINT"
  grep -qs " ${MOUNT_POINT} " /proc/mounts && return 0
  for dev in /dev/sd[a-z][0-9]* /dev/mmcblk[0-9]p[0-9]*; do
    [ -b "$dev" ] || continue
    grep -qs "^${dev} " /proc/mounts && continue
    logger -t mount-opt "mounting ${dev} -> ${MOUNT_POINT}"
    mount -o rw,noatime "$dev" "$MOUNT_POINT" && return 0
  done
  return 1
}
do_umount() {
  local dev="${1}"
  grep -qs "^${dev} ${MOUNT_POINT} " /proc/mounts && umount "$MOUNT_POINT"
}
case "$1" in
  mount) do_mount ;;
  umount) do_umount "$2" ;;
  *) echo "usage: $0 mount|umount [dev]" ;;
esac
EOF
  chmod +x files/usr/bin/mount-opt

  cat > files/etc/hotplug.d/block/40-mount-opt <<'EOF'
case "$ACTION" in
  add)
    case "$DEVNAME" in
      sd[a-z][0-9]*|mmcblk[0-9]p[0-9]*)
        ( sleep 1; /usr/bin/mount-opt mount ) &
        ;;
    esac
    ;;
  remove)
    case "$DEVNAME" in
      sd[a-z][0-9]*|mmcblk[0-9]p[0-9]*)
        /usr/bin/mount-opt umount "/dev/$DEVNAME"
        ;;
    esac
    ;;
esac
EOF

  cat > files/etc/uci-defaults/99-mount-opt <<'EOF'
#!/bin/sh
[ -x /etc/init.d/blockd ] && /etc/init.d/blockd disable
mkdir -p /opt
( n=0
while [ "$n" -lt 10 ] && ! /usr/bin/mount-opt mount; do
  sleep 1
  n=$((n+1))
done ) &
exit 0
EOF
  chmod +x files/etc/uci-defaults/99-mount-opt
  echo "✅ [7.7] USB auto-mount overlay generated"
fi

# ================================================================
# [7.9] /etc/sysctl.conf 内核调优
# ================================================================
if [ "${ENABLE_SYSCTL_TUNING}" = "1" ]; then
  mkdir -p files/etc
  cat > files/etc/sysctl.conf <<'EOF'
# ===========================================
# XG040MD (AN7581 / 无 WiFi / USB 扩展) 内核调优
# ===========================================
#### 1. 内存管理 ####
vm.swappiness = 0
vm.min_free_kbytes = 32768
vm.overcommit_memory = 0
vm.vfs_cache_pressure = 150
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
kernel.panic = 10

#### 2. 网络核心缓冲区 ####
net.core.rmem_max = 4194304
net.core.wmem_max = 4194304
net.core.rmem_default = 131072
net.core.wmem_default = 131072
net.core.netdev_max_backlog = 2000
net.core.netdev_budget = 600
net.core.somaxconn = 4096

#### 3. 游戏 UDP 保活 ####
net.netfilter.nf_conntrack_udp_timeout = 90
net.netfilter.nf_conntrack_udp_timeout_stream = 180

#### 4. TCP 协议栈 ####
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_mem = 8192 12288 16384
net.ipv4.tcp_rmem = 4096 131072 4194304
net.ipv4.tcp_wmem = 4096 131072 4194304
net.ipv4.tcp_max_tw_buckets = 16384
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_mtu_probing = 1

#### 5. UDP 协议栈水位 ####
net.ipv4.udp_mem = 8192 12288 16384
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384

#### 6. 连接追踪 ####
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_buckets = 16384
net.netfilter.nf_conntrack_tcp_timeout_established = 1200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 60

#### 7. 端口 / ARP / 文件句柄 ####
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
fs.file-max = 65536

#### 8. 安全加固 ####
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

#### 9. IPTV ####
net.ipv4.conf.all.force_igmp_version = 2
net.ipv4.conf.default.force_igmp_version = 2
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF
  echo "✅ [7.9] files/etc/sysctl.conf overlay generated"
fi

# ================================================================
# [10] 默认 LAN IP / hostname / 时区
# ================================================================
CFG="package/base-files/files/bin/config_generate"
if [ -f "$CFG" ]; then
  python3 - "$CFG" <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
lan_ip = os.environ.get("LAN_IP", "192.168.2.1")
hostname = os.environ.get("LAN_HOSTNAME", "XG040MD")

def must_replace(pattern, repl, label):
    global s
    s2, n = re.subn(pattern, repl, s, count=1)
    if n != 1:
        raise SystemExit(f"ERROR: config_generate patch failed: {label}")
    s = s2

must_replace(
    r'lan\) ipad=\$\{ipaddr:-"192\.168\.1\.1"\} ;;',
    'lan) ipad=${ipaddr:-"' + lan_ip + '"} ;;',
    "lan ip",
)
must_replace(
    r"(set system\.@system\[-?\d+\]\.hostname=)'[^']*'",
    "\\g<1>'" + hostname + "'",
    "hostname",
)
must_replace(
    r"(set system\.@system\[-?\d+\]\.timezone=)'[^']*'",
    "\\g<1>'CST-8'",
    "timezone",
)
must_replace(
    r"(set system\.@system\[-?\d+\]\.zonename=)'[^']*'",
    "\\g<1>'Asia/Shanghai'",
    "zonename",
)
open(p, "w", encoding="utf-8").write(s)
print("config_generate patched OK: LAN=" + lan_ip + " hostname=" + hostname + " TZ=Asia/Shanghai (CST-8)")
PY
  echo "--- patch result ---"
  grep -n "$LAN_IP" "$CFG" || true
  grep -n "$LAN_HOSTNAME" "$CFG" || true
  grep -n "CST-8" "$CFG" || true
else
  echo "::warning::未找到 $CFG，跳过默认 LAN/主机名/时区修改"
fi

# ================================================================
# [10.5] uci-defaults 强制中国时区
# ================================================================
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-timezone-cn <<'EOF'
#!/bin/sh
[ -s /etc/config/system ] || exit 0
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].timezone='CST-8'
uci -q commit system
exit 0
EOF
chmod +x files/etc/uci-defaults/99-timezone-cn
echo "✅ [10.5] uci-defaults 99-timezone-cn 已写入"

# ================================================================
# [10.6] NTP 服务器配置
# ================================================================
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-ntp-servers <<'EOF'
#!/bin/sh
# 配置 NTP 服务器
uci -q set system.ntp='timeserver'
uci -q set system.ntp.enabled='1'
uci -q set system.ntp.enable_server='0'

# 设置 NTP 服务器列表
uci -q delete system.ntp.server
uci -q add_list system.ntp.server='ntp.ntsc.ac.cn'
uci -q add_list system.ntp.server='ntp1.aliyun.com'
uci -q add_list system.ntp.server='cn.pool.ntp.org'
uci -q add_list system.ntp.server='time.cloudflare.com'

uci -q commit system
exit 0
EOF
chmod +x files/etc/uci-defaults/99-ntp-servers
echo "✅ [10.6] NTP 服务器配置已写入"

# ================================================================
# [10.7] ttyd Web 终端配置
# ================================================================
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-ttyd <<'EOF'
#!/bin/sh
# 配置 ttyd 自动登录（无需密码，方便调试）
uci -q set ttyd.@ttyd[0].command='/bin/login'
uci -q set ttyd.@ttyd[0].interface='@lan'
uci -q set ttyd.@ttyd[0].port='7681'
uci -q set ttyd.@ttyd[0].debug='0'
uci -q commit ttyd
exit 0
EOF
chmod +x files/etc/uci-defaults/99-ttyd
echo "✅ [10.7] ttyd 配置已写入"

# ================================================================
# [10.8] 定时重启配置（每天凌晨 4 点重启）
# ================================================================
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-autoreboot <<'EOF'
#!/bin/sh
# 配置定时重启：每天凌晨 4 点
uci -q set autoreboot.@autoreboot[0].enable='1'
uci -q set autoreboot.@autoreboot[0].time='04:00'
uci -q set autoreboot.@autoreboot[0].week='*'
uci -q commit autoreboot
exit 0
EOF
chmod +x files/etc/uci-defaults/99-autoreboot
echo "✅ [10.8] 定时重启配置已写入"

# ================================================================
# [10.9] USB 无线网卡热插拔支持
# ================================================================
mkdir -p files/etc/hotplug.d/usb
cat > files/etc/hotplug.d/usb/20-wifi-drivers <<'EOF'
#!/bin/sh
# USB 无线网卡驱动自动加载
case "$ACTION" in
  add)
    # 常见 USB WiFi 芯片 ID 自动加载对应驱动
    case "$PRODUCT" in
      # Realtek 8811CU
      2357/0126/*) modprobe 8811cu ;;
      # Realtek 88x2bu
      0bda/b812/*) modprobe 88x2bu ;;
      # MediaTek mt76x2u
      0e8d/7612/*) modprobe mt76x2u ;;
      # Realtek 8812au
      0bda/8812/*) modprobe 8812au ;;
      # Realtek 8821cu
      0bda/c811/*) modprobe 8821cu ;;
      # Realtek 8814au
      0bda/8814/*) modprobe 8814au ;;
      # Realtek 8723bu
      0bda/b720/*) modprobe 8723bu ;;
      # Realtek 8192eu
      0bda/818b/*) modprobe 8192eu ;;
      # MediaTek MT7921U
      0e8d/7961/*) modprobe mt7921u ;;
    esac
    ;;
esac
EOF
chmod +x files/etc/hotplug.d/usb/20-wifi-drivers
echo "✅ [10.9] USB 无线驱动热插拔脚本已写入"

# ================================================================
# zoneinfo-asia —— 亚洲时区数据库
# ================================================================
if [ -f .config ]; then
  sed -i '/^CONFIG_PACKAGE_zoneinfo-asia=/d; /^# CONFIG_PACKAGE_zoneinfo-asia is not set/d' .config
  echo "CONFIG_PACKAGE_zoneinfo-asia=y" >> .config
  echo "✅ zoneinfo-asia 已加入 .config"
fi

# ================================================================
# 固件版本后缀
# ================================================================
[ -z "$FW_BUILD_TIME" ] && FW_BUILD_TIME="$(TZ="${TZ:-Asia/Shanghai}" date '+%Y-%m-%d %H:%M')"
VER_CODE="$(sed -n 's/^CONFIG_VERSION_CODE="\(.*\)"$/\1/p' .config 2>/dev/null || true)"
if [ -n "$VER_CODE" ]; then
  DESC_BODY='%D %V %C'
else
  DESC_BODY='%D %V'
fi
[ -z "$FW_DESC_SUFFIX" ] && FW_DESC_SUFFIX="· ${FW_AUTHOR} · ${FW_BUILD_TIME}"
RELEASE_TPL="package/base-files/files/etc/openwrt_release"
OSREL_TPL="package/base-files/files/usr/lib/os-release"
FW_DESC_LINE="DISTRIB_DESCRIPTION='${DESC_BODY} ${FW_DESC_SUFFIX}'"
OSREL_LINE="OPENWRT_RELEASE=\"${DESC_BODY} ${FW_DESC_SUFFIX}\""
export FW_DESC_LINE OSREL_LINE
if [ -f "$RELEASE_TPL" ]; then
  perl -i -pe 's/^DISTRIB_DESCRIPTION=.*/$ENV{FW_DESC_LINE}/' "$RELEASE_TPL"
  echo "✅ 固件版本模板 -> $FW_DESC_LINE"
else
  echo "::warning::未找到 $RELEASE_TPL，固件版本不会带构建信息"
fi
if [ -f "$OSREL_TPL" ]; then
  perl -i -pe 's/^OPENWRT_RELEASE=.*/$ENV{OSREL_LINE}/' "$OSREL_TPL"
  echo "✅ os-release 同步 -> $OSREL_LINE"
fi

# ================================================================
# [11] 代理插件注入
# ================================================================
if [ -f .config ]; then
  case "$PROXY_VARIANT" in
    openclash)
      cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-i18n-openclash-zh-cn=y
CONFIG_PACKAGE_coreutils-nohup=y
CONFIG_PACKAGE_bash=y
EOF
      ;;
    dae)
      cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-dae=y
CONFIG_PACKAGE_luci-i18n-dae-zh-cn=y
EOF
      ;;
    honk)
      cat >> .config <<'EOF'
CONFIG_PACKAGE_luci-app-honk=y
CONFIG_PACKAGE_honk=y
EOF
      ;;
  esac
  echo "✅ 代理插件 [$PROXY_VARIANT] 已注入 .config"
fi

# ================================================================
# [12] 自定义包开关 —— defconfig 前最后一手
# ================================================================
if [ -f .config ]; then
  # 禁用指定的包
  if [ -n "$DISABLE_PACKAGES" ]; then
    for pkg in $DISABLE_PACKAGES; do
      sed -i "/^CONFIG_PACKAGE_${pkg}=/d; /^# CONFIG_PACKAGE_${pkg} is not set/d" .config
      echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
      sed -i "/^CONFIG_DEFAULT_${pkg}=/d; /^# CONFIG_DEFAULT_${pkg} is not set/d" .config
      echo "# CONFIG_DEFAULT_${pkg} is not set" >> .config
      sed -i "/^CONFIG_MODULE_DEFAULT_${pkg}=/d; /^# CONFIG_MODULE_DEFAULT_${pkg} is not set/d" .config
      echo "# CONFIG_MODULE_DEFAULT_${pkg} is not set" >> .config
    done
    echo "✅ 已禁用包: $DISABLE_PACKAGES"
  fi

  cat >> .config <<'EOF'
# ==== 自定义配置 ====
# 附加应用
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y
CONFIG_PACKAGE_luci-app-autoreboot=y
CONFIG_PACKAGE_luci-i18n-autoreboot-zh-cn=y
CONFIG_PACKAGE_luci-app-uhttpd=y
CONFIG_PACKAGE_luci-ssl-openssl=y
CONFIG_PACKAGE_acme-acmesh-dnsapi=y
CONFIG_PACKAGE_luci-app-acme=y

# 基础工具
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_vim-fuller=y
CONFIG_PACKAGE_kmod-regulator-userspace-consumer=y

# 硬件加速
CONFIG_PACKAGE_kmod-crypto-hw-eip93=y
CONFIG_PACKAGE_kmod-cryptodev=y
CONFIG_PACKAGE_kmod-sched-bpf=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
CONFIG_PACKAGE_libopenssl-devcrypto=y
CONFIG_PACKAGE_bpftool=y
CONFIG_PACKAGE_kmod-veth=y

# 关闭默认主题
# CONFIG_PACKAGE_luci-theme-bootstrap is not set

EOF

  # 替换默认主题为 Argon
  sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g; s/default Bootstrap theme/Argon theme/g' feeds/luci/collections/luci-light/Makefile 2>/dev/null || true

  # 移除不需要的 LuCI 菜单
  python3 - <<'PY' || true
import json
menus = {
  'feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json': 'admin/system/plugins',
  'feeds/luci/modules/luci-mod-network/root/usr/share/luci/menu.d/luci-mod-network.json': 'admin/network/diagnostics',
}
for path, node in menus.items():
  try:
    with open(path) as f:
      data = json.load(f)
    data.pop(node, None)
    with open(path, 'w') as f:
      json.dump(data, f, indent='\t')
  except:
    pass
PY
  rm -f feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/plugins.js 2>/dev/null
  rm -f feeds/luci/modules/luci-mod-network/htdocs/luci-static/resources/view/network/diagnostics.js 2>/dev/null

  echo "✅ 自定义包配置完成"
fi

echo "🎉 diy-part2.sh 执行完毕 (author=${FW_AUTHOR:-huazhou2026})"