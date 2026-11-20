#!/usr/bin/env bash
# ================================================================
# diy-part1.sh —— 拉取可选插件到 package/custom 并校验索引
# 运行目录：ponwrt 源码根目录（feeds 安装之后、加载 .config 之前）
# 用法：把需要的插件开关改成 true，再到 configs/<机型>.config 里
# 把对应 "# CONFIG_PACKAGE_xxx is not set" 改成 "=y"
# ================================================================
set -Eeuo pipefail
IFS=$'\n\t'
readonly SCRIPT_START=$(date +%s)
readonly PKG_DIR="$(pwd)/package/custom"
readonly PKGINFO="tmp/.packageinfo"

# ---------------------------------------------------------
# 插件开关（显式声明每一个，避免未定义变量）
# ---------------------------------------------------------
readonly ADD_AIROHA_NPU=true
readonly ADD_OPENCLASH=false
readonly ADD_DAE=false
readonly ADD_HONK=false
# USB WiFi 驱动已在官方 feeds 中（kmod-rtl8812au-ct, kmod-rtl8821cu 等），无需额外克隆
readonly ADD_USB_WIFI_DRIVERS=false

# ---------------------------------------------------------
# 插件清单——"开关 + 仓库 + 目录 + 分支"集中在这里
# 仅包含需要从外部仓库拉取的 LuCI 应用（内核模块走 feeds）
# ---------------------------------------------------------
readonly PKG_LIST=(
  "luci-app-airoha-npu|${ADD_AIROHA_NPU}|https://github.com/luanmuc/luci-app-airoha-npu|main"
  "luci-app-openclash|${ADD_OPENCLASH}|https://github.com/vernesong/OpenClash|dev"
  "luci-app-dae|${ADD_DAE}|https://github.com/QiuSimons/luci-app-dae|main"
  "honk|${ADD_HONK}|https://github.com/QiuSimons/luci-app-honk|main"
)

log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "::error::$*" >&2; exit 1; }
group() { echo "::group::$*"; }
endgroup(){ echo "::endgroup::"; }

retry() {
  local attempts=$1 max=$2; shift 2
  while (( attempts <= max )); do
    if "$@"; then return 0; fi
    local rc=$?
    log " ↻ 第 ${attempts}/${max} 次失败（rc=${rc}），${attempts}0s 后重试…"
    sleep $(( attempts * 10 ))
    attempts=$(( attempts + 1 ))
  done
  return 1
}

clone() {
  local url="$1" dir="$2" br="${3:-}" filter="${4:---depth=1}"
  if [ -d "$dir/.git" ]; then
    log " ↷ 已存在，跳过: $dir"
    return 0
  fi
  rm -rf "$dir"
  local log_file
  log_file="$(mktemp /tmp/clone-XXXXXX.log)"
  local args=(git clone --progress $filter)
  [ -n "$br" ] && args+=(-b "$br")
  args+=("$url" "$dir")
  log " ⤓ $(basename "$url") -> $dir"
  if ! retry 1 3 "${args[@]}" >"$log_file" 2>&1; then
    echo "--- git clone 失败，完整日志 ---" >&2
    cat "$log_file" >&2
    echo "-----------------------------------" >&2
    rm -f "$log_file"
    return 1
  fi
  rm -f "$log_file"
  if [ ! -f "$dir/Makefile" ]; then
    log " ⚠ $dir 无根 Makefile，视为源仓库/子包容器"
  fi
  local commit
  commit=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  log " ✅ $(basename "$dir") @ ${commit}"
}

# ================================================================
# 主流程
# ================================================================
group "拉取可选插件 (diy-part1.sh)"
mkdir -p "$PKG_DIR"
endgroup

group "克隆插件仓库（共 ${#PKG_LIST[@]} 项清单）"
ENABLED_COUNT=0
FAILED_PKGS=()
for entry in "${PKG_LIST[@]}"; do
  IFS='|' read -r name enabled url branch <<<"$entry"
  if [ "$enabled" != "true" ]; then
    log " ⊘ $name 未启用"
    continue
  fi
  ENABLED_COUNT=$((ENABLED_COUNT + 1))
  if ! clone "$url" "$PKG_DIR/$name" "$branch"; then
    FAILED_PKGS+=("$name")
    echo "::error::克隆失败: $name ($url)"
  fi
done
endgroup

# 特殊处理：openclash 放入 feeds/luci
if [ "$ADD_OPENCLASH" = "true" ]; then
  group "配置 OpenClash"
  rm -rf feeds/luci/applications/luci-app-openclash
  clone https://github.com/vernesong/OpenClash feeds/luci/applications/luci-app-openclash dev
  endgroup
fi

# 特殊处理：dae/honk
if [ "$ADD_DAE" = "true" ]; then
  group "配置 DAE"
  rm -rf feeds/luci/applications/luci-app-dae
  clone https://github.com/QiuSimons/luci-app-dae feeds/luci/applications/luci-app-dae main
  endgroup
fi

if [ "$ADD_HONK" = "true" ]; then
  group "配置 Honk"
  rm -rf feeds/luci/applications/luci-app-honk
  clone https://github.com/QiuSimons/luci-app-honk "$PKG_DIR/honk" main
  endgroup
fi

(( ${#FAILED_PKGS[@]} == 0 )) || die "以下插件克隆失败: ${FAILED_PKGS[*]}"

group "清理重复嵌套目录"
while IFS= read -r mkfile; do
  pkg_dir="$(dirname "$mkfile")"
  pkg_name="$(basename "$pkg_dir")"
  nested="$pkg_dir/$pkg_name"
  if [ -d "$nested" ] && [ -f "$nested/Makefile" ]; then
    rm -rf "$nested"
    log " ✂ 已移除重复嵌套目录: $pkg_name/$pkg_name"
  fi
done < <(find "$PKG_DIR" -mindepth 2 -maxdepth 2 -type f -name Makefile)
endgroup

group "重建包索引"
rm -f tmp/.packageinfo tmp/.targetinfo
rm -f tmp/info/.scan-packageinfo.stamp tmp/info/.scan-targetinfo.stamp
rm -f tmp/.config-package.in tmp/.config-target.in
make -s prepare-tmpinfo OPENWRT_BUILD= 2>&1 | tail -5 || true
[ -s "$PKGINFO" ] || die "$PKGINFO 为空，prepare-tmpinfo 失败"
log " ✅ tmp/.packageinfo 共 $(grep -c '^Package: ' "$PKGINFO") 个包"
endgroup

group "包索引校验"
INDEX_MISS=()
for d in "$PKG_DIR"/*; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  [ -f "$d/Makefile" ] || { log " ⊘ $n（无根 Makefile，跳过）"; continue; }
  if grep -qx "Package: $n" "$PKGINFO"; then
    log " ✅ $n"
  else
    log " ❌ $n 未进索引"
    INDEX_MISS+=("$n")
    for f in "logs/package/$n/dump.txt" "logs/package/custom/$n/dump.txt"; do
      [ -f "$f" ] && { echo "===== $f ====="; tail -25 "$f"; }
    done
  fi
done
endgroup

group "必装插件硬校验"
CRITICAL_PKGS=(luci-app-airoha-npu)
[ -f feeds/luci/luci.mk ] || die "feeds/luci/luci.mk 缺失，LuCI app 无法解析"
HARD_MISS=()
for r in "${CRITICAL_PKGS[@]}"; do
  grep -qx "Package: $r" "$PKGINFO" || HARD_MISS+=("$r")
done
if (( ${#HARD_MISS[@]} > 0 )); then
  for m in "${HARD_MISS[@]}"; do
    echo "::error::必装插件 $m 未进索引，defconfig 会静默剔除 =y"
  done
  exit 1
fi
log " ✅ 必装插件全部就绪: ${CRITICAL_PKGS[*]}"
endgroup

# ================================================================
# 输出 GitHub Step Summary
# ================================================================
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## diy-part1.sh 执行报告"
    echo ""
    echo "| 项目 | 值 |"
    echo "|---|---|"
    echo "| 启用插件 | ${ENABLED_COUNT} / ${#PKG_LIST[@]} |"
    echo "| 索引缺失 | ${INDEX_MISS[*]:-无} |"
    echo "| 必装校验 | ✅ 通过（${CRITICAL_PKGS[*]}） |"
    echo "| 耗时 | $(( $(date +%s) - SCRIPT_START ))s |"
  } >> "$GITHUB_STEP_SUMMARY"
fi
log "🎉 diy-part1.sh 执行完毕"