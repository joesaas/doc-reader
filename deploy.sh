#!/usr/bin/env bash
# doc-reader（Agent 101）运维脚本：更新代码 / 构建 / 启停服务 / 看日志 / 健康检查。
# 用法：./deploy.sh <操作>./deploy.sh help 查看全部操作。
#
# 服务只有一个：pm2 进程（历史名 index，现名 doc-reader，脚本自动识别；
# 可用环境变量 DOC_READER_PM2_NAME 强制指定）。入口 dist/server/src/index.js，
# 端口由 PORT 环境变量 /.env 决定，默认 3001。服务启动时自己加载.env。

set -uo pipefail
cd "$(dirname "$0")"

PORT="${PORT:-3001}"
PUBLIC_BASE="${PUBLIC_BASE:-https://agent101.uk}"

if [ -t 1 ]; then
B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
B=""; G=""; R=""; Y=""; N=""
fi
info() { echo "${B}==>${N} $*";}
ok() { echo "${G}✓${N} $*";}
warn() { echo "${Y}!${N} $*";}
die() { echo "${R}✗ $*${N}" >&2; exit 1;}

need() { command -v "$1" >/dev/null 2>&1 || die "找不到命令：$1";}

# 识别当前 pm2 进程名：doc-reader 优先，其次历史名 index；都没有时返回 doc-reader（待启动）
app_name() {
if [ -n "${DOC_READER_PM2_NAME:-}" ]; then
echo "$DOC_READER_PM2_NAME"; return
fi
if pm2 describe doc-reader >/dev/null 2>&1; then
echo "doc-reader"; return
fi
if pm2 describe index >/dev/null 2>&1; then
echo "index"; return
fi
echo "doc-reader"
}

cmd_help() {
cat <<'EOF'
doc-reader（Agent 101）运维脚本

用法：./deploy.sh <操作>


deploy 全流程：拉代码 -> 装依赖 -> 构建 -> 重启 -> 状态
update 只拉最新代码（git pull）
build 只装依赖并构建（npm install + npm run build：tsc 后端 + vite 前端）

（单服务，无需填服务名）
start 启动（pm2 start dist/server/src/index.js --name doc-reader）
stop 停止
restart 重启（进程不存在时自动改为启动）
status 查看全部 pm2 进程
logs [行数] 看日志（默认最近 50 行）


health 健康检查：本机服务 / 公网首页 / 公网 AI API
smoke 跑项目自检（npm run smoke + smoke:ai，需服务在运行）


help 显示本帮助

示例：
./deploy.sh deploy # 整体更新上线
./deploy.sh logs 100 # 看最近 100 行日志
EOF
}

cmd_update() {
info "拉取最新代码…"
git pull --ff-only || die "git pull 失败（有本地改动先处理，或检查 deploy key）"
ok "代码已更新到 $(git rev-parse --short HEAD)"
}

cmd_build() {
need npm
info "安装依赖…"
npm install || die "npm install 失败"
info "构建（tsc 后端 + vite 前端）…"
npm run build || die "构建失败"
ok "构建完成"
}

cmd_start() {
need pm2
local name; name="$(app_name)"
info "启动 $name…"
pm2 start dist/server/src/index.js --name "$name" || die "启动失败，看./deploy.sh logs"
pm2 save >/dev/null
ok "已启动并 pm2 save"
}

cmd_stop() {
need pm2
local name; name="$(app_name)"
pm2 stop "$name" || die "停止 $name 失败"
pm2 save >/dev/null
ok "已停止"
}

cmd_restart() {
need pm2
local name; name="$(app_name)"
if pm2 describe "$name" >/dev/null 2>&1; then
info "重启 $name…"
pm2 restart "$name" || die "重启 $name 失败"
pm2 save >/dev/null
ok "重启完成"
else
warn "$name 不在 pm2 中，改为启动"
cmd_start
fi
}

cmd_status() {
need pm2
pm2 list
}

cmd_logs() {
need pm2
local name; name="$(app_name)"
pm2 logs "$name" --lines "${1:-50}" --nostream
}

check() { # check <说明> <命令...>
local label="$1"; shift
if "$@" >/dev/null 2>&1; then ok "$label"; else warn "$label —— 未通过"; fi
}

cmd_health() {
echo "${B}健康检查${N}"
check "本机服务 (localhost:$PORT)" curl -sf -m 5 "http://localhost:$PORT/"
check "公网首页 ($PUBLIC_BASE)" curl -sf -m 8 "$PUBLIC_BASE/"
check "公网 AI API 能力发现 ($PUBLIC_BASE/api/ai)" curl -sf -m 8 "$PUBLIC_BASE/api/ai"
need pm2 && pm2 describe "$(app_name)" >/dev/null 2>&1 && ok "pm2 进程 $(app_name) 存在" || warn "pm2 进程未找到"
}

cmd_smoke() {
need npm
info "跑基础自检 smoke…"
npm run smoke || die "smoke 未通过"
info "跑 AI API 自检 smoke:ai…"
npm run smoke:ai || die "smoke:ai 未通过"
ok "自检全部通过"
}

main() {
local action="${1:-help}"
case "$action" in
help|-h|--help) cmd_help;;
update) cmd_update;;
build) cmd_build;;
deploy)
cmd_update
cmd_build
cmd_restart
cmd_status
;;
start) cmd_start;;
stop) cmd_stop;;
restart) cmd_restart;;
status) cmd_status;;
logs) cmd_logs "${2:-50}";;
health) cmd_health;;
smoke) cmd_smoke;;
*) echo "${R}未知操作：$action${N}" >&2; echo; cmd_help; exit 1;;
esac
}

main "$@"
