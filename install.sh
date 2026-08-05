#!/usr/bin/env bash
set -Eeuo pipefail

# VoHive binary-only installer for archived historical releases.
# Downloads verified precompiled assets from the release repository.
RELEASE_REPO="${VOHIVE_RELEASE_REPO:-zhangsan-nb/vohive-release}"
DEFAULT_VERSION="v1.5.5-10-gf9eb85d"

VERSION=""
NO_SYSTEMD=0
FORCE_CONFIG=0
DRY_RUN=0

ROOT_DIR="${VOHIVE_ROOT_DIR:-/opt/vohive}"
INSTALL_DIR="${ROOT_DIR}/bin"
CONFIG_DIR="${ROOT_DIR}/config"
DATA_DIR="${ROOT_DIR}/data"
LOG_DIR="${ROOT_DIR}/logs"
BIN_PATH="${INSTALL_DIR}/vohive"
BACKUP_PATH="${INSTALL_DIR}/vohive.bak"
SERVICE_PATH="/etc/systemd/system/vohive.service"
QMI_RECOVER_SCRIPT_PATH="/usr/local/sbin/vohive-qmi-recover"
QMI_RECOVER_SERVICE_PATH="/etc/systemd/system/vohive-qmi-recover.service"
QMI_RECOVER_RULE_PATH="/etc/udev/rules.d/99-vohive-qmi-recover.rules"

TMP_DIR=""
NEW_PASSWORD=""

log() { printf '[vohive-install] %s\n' "$*"; }
warn() { printf '[vohive-install] 警告: %s\n' "$*" >&2; }
err() { printf '[vohive-install] 错误: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
用法: install.sh [选项]
  --version <版本>          安装指定的已验证预编译版本；默认 v1.5.5-10-gf9eb85d
  --source-ref <引用>       已弃用；为兼容旧命令而接受，但不会触发源码编译
  --binary-only             兼容选项；当前安装器始终只使用预编译二进制
  --no-systemd              只安装，不创建或启动 systemd 服务
  --force-config            重建最小配置（会先备份原配置）
  --dry-run                 只显示会执行的本机安装操作
  -h, --help                显示帮助

可选环境变量:
  VOHIVE_RELEASE_REPO       默认 zhangsan-nb/vohive-release
  VOHIVE_ROOT_DIR           默认 /opt/vohive
USAGE
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

on_error() {
  local rc=$?
  err "安装在第 ${BASH_LINENO[0]:-未知} 行失败（退出码 ${rc}）。"
  if [[ -f "${BACKUP_PATH}" && -x "${BACKUP_PATH}" ]]; then
    warn "旧版本备份仍保留在 ${BACKUP_PATH}，可手动恢复。"
  fi
  exit "${rc}"
}
trap on_error ERR

run_root() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    err "需要 root 权限。请用 root 登录，或先安装 sudo。"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "缺少必要命令: $1"
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || { err "--version 缺少参数"; exit 1; }
        VERSION="$2"; shift 2 ;;
      --source-ref)
        [[ $# -ge 2 ]] || { err "--source-ref 缺少参数"; exit 1; }
        warn "--source-ref 已弃用，当前安装器不支持源码编译。该参数将被忽略。"
        shift 2 ;;
      --binary-only) shift ;; # 兼容选项；当前始终只使用预编译二进制
      --no-systemd) NO_SYSTEMD=1; shift ;;
      --force-config) FORCE_CONFIG=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) err "未知参数: $1"; usage; exit 1 ;;
    esac
  done
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    armv7|armv7l) printf 'armv7\n' ;;
    *) err "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
  esac
}

is_elf() {
  [[ -s "$1" ]] || return 1
  [[ "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" == "7f454c46" ]]
}

known_binary_sha256() {
  local tag="$1" arch="$2"
  case "${tag}:${arch}" in
    v1.5.5-10-gf9eb85d:amd64) printf '%s\n' '841d117d4921718b2627a6485b09c62d858c088e42e6e55468ae0f3e0ece1bdd' ;;
    v1.5.5-10-gf9eb85d:arm64) printf '%s\n' '4cbfcec06b719609f3d88714b4df63c420e1cf958fbad0b4851a3c495c595661' ;;
    v1.5.5-10-gf9eb85d:armv7) printf '%s\n' '682f3dc02a59bbbdb7128e71f212ca0a0c2d1825efa27e35bbf1537496625766' ;;
    *) return 1 ;;
  esac
}

try_binary() {
  local repo="$1" tag="$2" arch="$3" output="$4"
  local asset="vohive_${tag}_linux_${arch}" expected actual

  expected="$(known_binary_sha256 "${tag}" "${arch}" 2>/dev/null || true)"
  if [[ -z "${expected}" ]]; then
    warn "版本 ${tag} / 架构 ${arch} 没有已知 SHA-256，拒绝安装未经验证的资产"
    return 1
  fi

  local url="https://github.com/${repo}/releases/download/${tag}/${asset}"
  log "尝试预编译二进制: ${repo} / ${tag} / ${arch}"
  if ! curl -fL --retry 2 --connect-timeout 15 --progress-bar "${url}" -o "${output}"; then
    rm -f "${output}"
    return 1
  fi
  if ! is_elf "${output}"; then
    warn "下载结果不是有效的 Linux ELF 二进制，已忽略: ${url}"
    rm -f "${output}"
    return 1
  fi
  actual="$(sha256sum "${output}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    warn "二进制 SHA-256 校验失败，拒绝安装: ${asset}"
    rm -f "${output}"
    return 1
  fi
  log "SHA-256 校验通过: ${asset}"
  chmod 0755 "${output}"
  return 0
}

download_binary() {
  local arch="$1" output="$2" tag="${VERSION}"

  if [[ -z "${tag}" || "${tag}" == "latest" || "${tag}" == "stable" ]]; then
    tag="${DEFAULT_VERSION}"
    log "未指定版本，使用默认预编译版本: ${tag}"
  fi

  if try_binary "${RELEASE_REPO}" "${tag}" "${arch}" "${output}"; then
    printf '%s\n' "${tag}" > "${TMP_DIR}/installed-version"
    return 0
  fi
  return 1
}

random_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 12
  else
    od -An -N12 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

install_config() {
  local config_tmp="${TMP_DIR}/config.yaml"
  run_root mkdir -p "${INSTALL_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}"
  if [[ -f "${CONFIG_DIR}/config.yaml" && "${FORCE_CONFIG}" == "0" ]]; then
    log "保留现有配置: ${CONFIG_DIR}/config.yaml"
    return 0
  fi
  if [[ -f "${CONFIG_DIR}/config.yaml" ]]; then
    run_root cp -a "${CONFIG_DIR}/config.yaml" "${CONFIG_DIR}/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
  fi
  NEW_PASSWORD="$(random_password)"
  cat > "${config_tmp}" <<CFG
server:
  port: "7575"
  debug: false

web:
  username: "admin"
  password: "${NEW_PASSWORD}"

devices: []

vowifi:
  enabled: false
CFG
  run_root install -m 0600 "${config_tmp}" "${CONFIG_DIR}/config.yaml"
}

install_qmi_recovery() {
  local recover_script_tmp="${TMP_DIR}/vohive-qmi-recover"
  local recover_unit_tmp="${TMP_DIR}/vohive-qmi-recover.service"
  local recover_rule_tmp="${TMP_DIR}/99-vohive-qmi-recover.rules"

  if ! command -v udevadm >/dev/null 2>&1; then
    warn "系统没有 udevadm，跳过 EC25 QMI 重新枚举自动恢复补丁。"
    return 0
  fi

  cat > "${recover_script_tmp}" <<'RECOVER_SCRIPT'
#!/bin/sh
set -eu

TAG="vohive-qmi-recover"
STAMP="/run/${TAG}.last"
WAIT_SECONDS=15
COOLDOWN_SECONDS=60
MIN_SERVICE_AGE=60

sleep "${WAIT_SECONDS}"
udevadm settle --timeout=10 || true

set -- /dev/cdc-wdm*
if [ ! -e "$1" ]; then
    logger -t "${TAG}" "未发现 cdc-wdm 设备，取消恢复"
    exit 0
fi

if ! systemctl is-active --quiet vohive.service; then
    logger -t "${TAG}" "VoHive 当前未运行，取消恢复"
    exit 0
fi

ACTIVE_US="$(systemctl show vohive.service \
    -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)"
case "${ACTIVE_US}" in
    ''|*[!0-9]*) ACTIVE_US=0 ;;
esac

UPTIME_SECONDS="$(cut -d. -f1 /proc/uptime)"
if [ "${ACTIVE_US}" -gt 0 ]; then
    SERVICE_AGE=$((UPTIME_SECONDS - ACTIVE_US / 1000000))
    if [ "${SERVICE_AGE}" -lt "${MIN_SERVICE_AGE}" ]; then
        logger -t "${TAG}" "VoHive 刚启动 ${SERVICE_AGE} 秒，跳过重复恢复"
        exit 0
    fi
fi

NOW="$(date +%s)"
LAST=0
if [ -r "${STAMP}" ]; then
    LAST="$(cat "${STAMP}" 2>/dev/null || echo 0)"
fi
case "${LAST}" in
    ''|*[!0-9]*) LAST=0 ;;
esac

if [ $((NOW - LAST)) -lt "${COOLDOWN_SECONDS}" ]; then
    logger -t "${TAG}" "仍在冷却时间内，跳过重复恢复"
    exit 0
fi

printf '%s\n' "${NOW}" > "${STAMP}"
logger -t "${TAG}" "检测到 Quectel QMI 设备重新枚举，正在重启 VoHive"
systemctl restart vohive.service
logger -t "${TAG}" "VoHive 自动恢复完成"
RECOVER_SCRIPT

  cat > "${recover_unit_tmp}" <<'RECOVER_UNIT'
[Unit]
Description=Recover VoHive after QMI USB re-enumeration
After=systemd-udevd.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vohive-qmi-recover
TimeoutStartSec=90
RECOVER_UNIT

  cat > "${recover_rule_tmp}" <<'RECOVER_RULE'
# Quectel EC25 2c7c:0125: recover VoHive after the QMI control device returns
ACTION=="add", SUBSYSTEM=="usbmisc", KERNEL=="cdc-wdm*", ATTRS{idVendor}=="2c7c", ATTRS{idProduct}=="0125", TAG+="systemd", ENV{SYSTEMD_WANTS}+="vohive-qmi-recover.service"
RECOVER_RULE

  run_root mkdir -p /usr/local/sbin /etc/udev/rules.d
  run_root install -m 0755 "${recover_script_tmp}" "${QMI_RECOVER_SCRIPT_PATH}"
  run_root install -m 0644 "${recover_unit_tmp}" "${QMI_RECOVER_SERVICE_PATH}"
  run_root install -m 0644 "${recover_rule_tmp}" "${QMI_RECOVER_RULE_PATH}"
  log "已安装 EC25 QMI 重新枚举自动恢复补丁。"
}

install_systemd() {
  local unit_tmp="${TMP_DIR}/vohive.service"
  cat > "${unit_tmp}" <<UNIT
[Unit]
Description=VoHive Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${ROOT_DIR}
ExecStart=${BIN_PATH} -c ${CONFIG_DIR}/config.yaml
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
UNIT
  run_root install -m 0644 "${unit_tmp}" "${SERVICE_PATH}"
  install_qmi_recovery
  run_root systemctl daemon-reload
  if command -v udevadm >/dev/null 2>&1; then
    run_root udevadm control --reload-rules
  fi
  run_root systemctl enable vohive.service
  run_root systemctl restart vohive.service
  if [[ "${DRY_RUN}" == "0" ]] && ! run_root systemctl is-active --quiet vohive.service; then
    run_root journalctl -u vohive.service -n 40 --no-pager || true
    err "VoHive 服务启动失败，上方是最近日志。"
    return 1
  fi
}

install_binary() {
  local source_binary="$1"
  if [[ -x "${BIN_PATH}" ]]; then
    log "备份旧二进制: ${BACKUP_PATH}"
    run_root cp -f "${BIN_PATH}" "${BACKUP_PATH}"
  fi
  run_root install -m 0755 "${source_binary}" "${BIN_PATH}"
}

print_result() {
  local installed_version ips ip
  installed_version="$(cat "${TMP_DIR}/installed-version" 2>/dev/null || printf 'unknown')"
  log "安装完成: ${BIN_PATH} [${installed_version}]"
  if [[ "${NO_SYSTEMD}" == "1" ]]; then
    log "手动启动: cd ${ROOT_DIR} && ${BIN_PATH} -c ${CONFIG_DIR}/config.yaml"
  else
    log "服务状态: $(systemctl is-active vohive.service 2>/dev/null || printf 'unknown')"
  fi
  log "访问地址: http://127.0.0.1:7575"
  ips="$(hostname -I 2>/dev/null || true)"
  for ip in ${ips}; do
    [[ "${ip}" == *:* || "${ip}" == 127.* ]] && continue
    log "局域网访问: http://${ip}:7575"
  done
  log "Web 用户名: admin"
  if [[ -n "${NEW_PASSWORD}" ]]; then
    log "本次生成的 Web 密码: ${NEW_PASSWORD}"
    warn "请立即保存此密码；不要把 7575 端口直接暴露到公网。"
  else
    log "沿用现有配置中的 Web 密码。"
  fi
  log "查看日志: journalctl -u vohive -f"
}

main() {
  parse_args "$@"
  need_cmd curl
  need_cmd uname
  need_cmd od
  need_cmd sha256sum
  [[ "$(uname -s)" == "Linux" ]] || { err "仅支持 Linux"; exit 1; }

  local arch candidate
  arch="$(detect_arch)"
  TMP_DIR="$(mktemp -d)"
  candidate="${TMP_DIR}/vohive"

  if ! download_binary "${arch}" "${candidate}"; then
    err "未找到可用预编译二进制（架构: ${arch}）。"
    err "当前仅分发原作者遗留的历史预编译二进制 v1.5.5-10-gf9eb85d。"
    err "由于关键依赖不可公开获取，无法从源码自动编译。"
    err "请确认已发布 Release 资产后重试，或联系仓库维护者。"
    exit 1
  fi

  install_config
  install_binary "${candidate}"
  if [[ "${NO_SYSTEMD}" == "0" ]]; then
    need_cmd systemctl
    if ! install_systemd; then
      if [[ -x "${BACKUP_PATH}" ]]; then
        warn "启动失败，正在恢复旧二进制。"
        run_root cp -f "${BACKUP_PATH}" "${BIN_PATH}"
        run_root systemctl restart vohive.service || true
      fi
      exit 1
    fi
  fi
  print_result
}

main "$@"
