#!/usr/bin/env bash
set -Eeuo pipefail

REPO="${VOHIVE_RELEASE_REPO:-zhangsan-nb/vohive-release}"
API="${VOHIVE_GITHUB_API_ROOT:-https://api.github.com}"
ROOT_DIR="${VOHIVE_ROOT_DIR:-/opt/vohive}"
VERSION="latest"
TOKEN_FILE=""
NO_SYSTEMD=0
FORCE_CONFIG=0
TMP_DIR=""
TOKEN=""
NEW_PASSWORD=""

log(){ printf '[vohive-install] %s\n' "$*"; }
err(){ printf '[vohive-install] 错误: %s\n' "$*" >&2; exit 1; }
cleanup(){ TOKEN=""; unset VOHIVE_GITHUB_TOKEN GITHUB_TOKEN GH_TOKEN 2>/dev/null || true; [[ -n "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

usage(){ cat <<'USAGE'
用法: install-private.sh [选项]
  --version <tag|latest>  安装指定版本，默认 latest
  --token-file <path>     从文件读取 GitHub fine-grained token
  --no-systemd            不安装或启动 systemd 服务
  --force-config          重新生成最小配置（原配置会备份）
  -h, --help              显示帮助

Token 查找顺序：VOHIVE_GITHUB_TOKEN、GITHUB_TOKEN、GH_TOKEN、--token-file；
均未提供时，会从 /dev/tty 隐藏读取。Token 只用于本次 GitHub 下载，不写入 VoHive。
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) [[ $# -ge 2 ]] || err '--version 缺少参数'; VERSION="$2"; shift 2 ;;
    --token-file) [[ $# -ge 2 ]] || err '--token-file 缺少参数'; TOKEN_FILE="$2"; shift 2 ;;
    --no-systemd) NO_SYSTEMD=1; shift ;;
    --force-config) FORCE_CONFIG=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "未知参数: $1" ;;
  esac
done

[[ "$(uname -s)" == Linux ]] || err '仅支持 Linux'
for cmd in curl python3 sha256sum od install; do command -v "$cmd" >/dev/null || err "缺少命令: $cmd"; done

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  armv7|armv7l) ARCH=armv7 ;;
  *) err "不支持的架构: $(uname -m)" ;;
esac

TOKEN="${VOHIVE_GITHUB_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
if [[ -z "$TOKEN" && -n "$TOKEN_FILE" ]]; then
  [[ -r "$TOKEN_FILE" ]] || err "无法读取 Token 文件: $TOKEN_FILE"
  TOKEN="$(tr -d '\r\n' < "$TOKEN_FILE")"
fi
if [[ -z "$TOKEN" ]]; then
  [[ -r /dev/tty ]] || err '没有可交互终端，请通过 VOHIVE_GITHUB_TOKEN 提供 Token'
  read -rsp 'GitHub Token: ' TOKEN </dev/tty
  printf '\n' >/dev/tty
fi
[[ -n "$TOKEN" && "$TOKEN" != *[[:space:]]* ]] || err 'Token 为空或包含空白字符'

TMP_DIR="$(mktemp -d)"
CURL_CFG="$TMP_DIR/github.conf"
{
  printf '%s\n' 'silent' 'show-error' 'fail' 'location' 'retry = 2' 'connect-timeout = 15'
  printf 'header = "Authorization: Bearer %s"\n' "$TOKEN"
  printf '%s\n' 'header = "X-GitHub-Api-Version: 2022-11-28"'
} >"$CURL_CFG"
chmod 600 "$CURL_CFG"
api_get(){ curl --config "$CURL_CFG" -H 'Accept: application/vnd.github+json' "$API$1"; }

api_get "/repos/$REPO" >/dev/null 2>&1 || err "Token 无法读取 $REPO；请确认 Contents: Read-only 权限"

if [[ "$VERSION" == latest ]]; then
  RELEASE_JSON="$(api_get "/repos/$REPO/releases/latest")" || err '无法查询 latest Release'
else
  ENCODED_TAG="$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$VERSION")"
  RELEASE_JSON="$(api_get "/repos/$REPO/releases/tags/$ENCODED_TAG")" || err "找不到 Release: $VERSION"
fi

readarray -t RELEASE_INFO < <(printf '%s' "$RELEASE_JSON" | python3 -c '
import json,sys
r=json.load(sys.stdin)
tag=r.get("tag_name","")
arch=sys.argv[1]
name=f"vohive_{tag}_linux_{arch}"
asset=next((a for a in r.get("assets",[]) if a.get("name")==name),None)
if not tag or not asset: raise SystemExit(2)
print(tag); print(asset["id"]); print(name)
' "$ARCH") || err "Release 中没有 $ARCH 二进制"
TAG="${RELEASE_INFO[0]}"; ASSET_ID="${RELEASE_INFO[1]}"; ASSET_NAME="${RELEASE_INFO[2]}"

BIN_TMP="$TMP_DIR/vohive"
log "下载 $ASSET_NAME"
curl --config "$CURL_CFG" -H 'Accept: application/octet-stream' \
  "$API/repos/$REPO/releases/assets/$ASSET_ID" -o "$BIN_TMP"
[[ "$(od -An -tx1 -N4 "$BIN_TMP" | tr -d ' \n')" == 7f454c46 ]] || err '下载结果不是 Linux ELF 二进制'
chmod 755 "$BIN_TMP"

EXPECTED=''
case "$TAG:$ARCH" in
  v1.5.5-10-gf9eb85d:amd64) EXPECTED=841d117d4921718b2627a6485b09c62d858c088e42e6e55468ae0f3e0ece1bdd ;;
  v1.5.5-10-gf9eb85d:arm64) EXPECTED=4cbfcec06b719609f3d88714b4df63c420e1cf958fbad0b4851a3c495c595661 ;;
  v1.5.5-10-gf9eb85d:armv7) EXPECTED=682f3dc02a59bbbdb7128e71f212ca0a0c2d1825efa27e35bbf1537496625766 ;;
esac
if [[ -n "$EXPECTED" ]]; then
  ACTUAL="$(sha256sum "$BIN_TMP" | awk '{print $1}')"
  [[ "$ACTUAL" == "$EXPECTED" ]] || err 'SHA-256 校验失败'
  log 'SHA-256 校验通过'
fi

BIN_DIR="$ROOT_DIR/bin"; CONFIG_DIR="$ROOT_DIR/config"; DATA_DIR="$ROOT_DIR/data"; LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR"
if [[ -x "$BIN_DIR/vohive" ]]; then cp -f "$BIN_DIR/vohive" "$BIN_DIR/vohive.bak"; fi
install -m 0755 "$BIN_TMP" "$BIN_DIR/vohive"
printf '%s\n' "$TAG" >"$ROOT_DIR/VERSION"

if [[ ! -f "$CONFIG_DIR/config.yaml" || "$FORCE_CONFIG" == 1 ]]; then
  [[ -f "$CONFIG_DIR/config.yaml" ]] && cp -a "$CONFIG_DIR/config.yaml" "$CONFIG_DIR/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
  if command -v openssl >/dev/null 2>&1; then NEW_PASSWORD="$(openssl rand -hex 12)"; else NEW_PASSWORD="$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')"; fi
  cat >"$CONFIG_DIR/config.yaml" <<CFG
server:
  port: "7575"
  debug: false
web:
  username: "admin"
  password: "$NEW_PASSWORD"
devices: []
vowifi:
  enabled: false
CFG
  chmod 600 "$CONFIG_DIR/config.yaml"
else
  log "保留现有配置: $CONFIG_DIR/config.yaml"
fi

if [[ "$NO_SYSTEMD" == 0 ]]; then
  command -v systemctl >/dev/null || err '系统没有 systemctl，可使用 --no-systemd'
  cat >/etc/systemd/system/vohive.service <<UNIT
[Unit]
Description=VoHive Service
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=$ROOT_DIR
ExecStart=$BIN_DIR/vohive -c $CONFIG_DIR/config.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable vohive.service >/dev/null
  if ! systemctl restart vohive.service; then
    [[ -x "$BIN_DIR/vohive.bak" ]] && cp -f "$BIN_DIR/vohive.bak" "$BIN_DIR/vohive"
    systemctl restart vohive.service 2>/dev/null || true
    err 'VoHive 启动失败，已尝试恢复旧二进制'
  fi
fi

log "安装完成: $BIN_DIR/vohive [$TAG]"
log '访问地址: http://127.0.0.1:7575'
log 'Web 用户名: admin'
[[ -n "$NEW_PASSWORD" ]] && log "本次生成的 Web 密码: $NEW_PASSWORD"
log 'Token 未写入 VoHive；下次安装或更新时重新提供即可。'
