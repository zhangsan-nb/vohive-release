#!/usr/bin/env bash
set -Eeuo pipefail

# VoHive one-click installer for the maintained forks.
# Binary lookup order: release repository -> source repository -> local source build.
RELEASE_REPO="${VOHIVE_RELEASE_REPO:-zhangsan-nb/vohive-release}"
SOURCE_REPO="${VOHIVE_SOURCE_REPO:-zhangsan-nb/vohive}"
SOURCE_REF="${VOHIVE_SOURCE_REF:-main}"

VERSION=""
NO_SYSTEMD=0
BINARY_ONLY=0
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

TMP_DIR=""
NEW_PASSWORD=""

log() { printf '[vohive-install] %s\n' "$*"; }
warn() { printf '[vohive-install] 警告: %s\n' "$*" >&2; }
err() { printf '[vohive-install] 错误: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
用法: install.sh [选项]
  --version <vX.Y.Z|latest>  安装指定 Release；默认先找 latest，找不到则编译 main
  --source-ref <分支或标签>  源码编译所用的分支/标签（默认 main）
  --binary-only             找不到预编译二进制时直接退出，不自动编译
  --no-systemd              只安装，不创建或启动 systemd 服务
  --force-config            重建最小配置（会先备份原配置）
  --dry-run                 只显示会执行的本机安装操作
  -h, --help                显示帮助

可选环境变量:
  VOHIVE_RELEASE_REPO       默认 zhangsan-nb/vohive-release
  VOHIVE_SOURCE_REPO        默认 zhangsan-nb/vohive
  VOHIVE_SOURCE_REF         默认 main
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
        SOURCE_REF="$2"; shift 2 ;;
      --binary-only) BINARY_ONLY=1; shift ;;
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

github_latest_tag() {
  local repo="$1" json
  json="$(curl -fsSL --retry 2 --connect-timeout 10 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null || true)"
  printf '%s' "${json}" | tr -d '\n' | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
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
  expected="$(known_binary_sha256 "${tag}" "${arch}" 2>/dev/null || true)"
  if [[ -n "${expected}" ]]; then
    actual="$(sha256sum "${output}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
      warn "二进制 SHA-256 校验失败，拒绝安装: ${asset}"
      rm -f "${output}"
      return 1
    fi
    log "SHA-256 校验通过: ${asset}"
  fi
  chmod 0755 "${output}"
  return 0
}

download_binary() {
  local arch="$1" output="$2" tag="${VERSION}" repo candidate
  local -a repos=("${RELEASE_REPO}" "${SOURCE_REPO}")

  if [[ -n "${tag}" && "${tag}" != "latest" && "${tag}" != "stable" ]]; then
    for repo in "${repos[@]}"; do
      if try_binary "${repo}" "${tag}" "${arch}" "${output}"; then
        printf '%s\n' "${tag}" > "${TMP_DIR}/installed-version"
        return 0
      fi
    done
    return 1
  fi

  for repo in "${repos[@]}"; do
    candidate="$(github_latest_tag "${repo}")"
    [[ -n "${candidate}" ]] || continue
    if try_binary "${repo}" "${candidate}" "${arch}" "${output}"; then
      printf '%s\n' "${candidate}" > "${TMP_DIR}/installed-version"
      return 0
    fi
  done
  return 1
}

install_build_dependencies() {
  local -a missing=()
  local cmd
  for cmd in git sha256sum tar; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  [[ ${#missing[@]} -gt 0 ]] || return 0

  if command -v apt-get >/dev/null 2>&1; then
    log "安装源码编译依赖（仅缺少时安装）: git ca-certificates coreutils tar"
    run_root apt-get update
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates coreutils tar
  else
    err "没有找到 apt-get。源码自动编译目前支持 Debian/Ubuntu；也可先发布二进制后使用 --binary-only。"
    exit 1
  fi
}

version_ge() {
  local current="$1" required="$2"
  [[ "$(printf '%s\n%s\n' "${required}" "${current}" | sort -V | head -n1)" == "${required}" ]]
}

prepare_go() {
  local required="$1" arch="$2" go_arch current archive checksum expected actual
  if command -v go >/dev/null 2>&1; then
    current="$(go env GOVERSION 2>/dev/null | sed 's/^go//' || true)"
    if [[ -n "${current}" ]] && version_ge "${current}" "1.21"; then
      command -v go
      return 0
    fi
  fi

  case "${arch}" in
    amd64) go_arch="amd64" ;;
    arm64) go_arch="arm64" ;;
    armv7) go_arch="armv6l" ;;
  esac
  archive="${TMP_DIR}/go.tar.gz"
  checksum="${archive}.sha256"
  log "准备临时 Go ${required} 编译环境" >&2
  curl -fL --retry 2 "https://go.dev/dl/go${required}.linux-${go_arch}.tar.gz" -o "${archive}"
  curl -fsSL --retry 2 "https://go.dev/dl/go${required}.linux-${go_arch}.tar.gz.sha256" -o "${checksum}"
  expected="$(tr -d '[:space:]' < "${checksum}")"
  actual="$(sha256sum "${archive}" | awk '{print $1}')"
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] || {
    err "Go 工具链 SHA-256 校验失败"; exit 1;
  }
  mkdir -p "${TMP_DIR}/go-toolchain"
  tar -xzf "${archive}" -C "${TMP_DIR}/go-toolchain"
  printf '%s\n' "${TMP_DIR}/go-toolchain/go/bin/go"
}

prepare_node() {
  local arch="$1" required="${VOHIVE_NODE_VERSION:-20.19.5}" node_arch current archive sums expected actual topdir
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    current="$(node --version 2>/dev/null | sed 's/^v//' || true)"
    if [[ -n "${current}" ]] && version_ge "${current}" "18.0.0"; then
      dirname "$(command -v node)"
      return 0
    fi
  fi

  case "${arch}" in
    amd64) node_arch="x64" ;;
    arm64) node_arch="arm64" ;;
    armv7) node_arch="armv7l" ;;
  esac
  archive="${TMP_DIR}/node.tar.gz"
  sums="${TMP_DIR}/node-SHASUMS256.txt"
  topdir="node-v${required}-linux-${node_arch}"
  log "准备临时 Node.js ${required} 编译环境" >&2
  curl -fL --retry 2 "https://nodejs.org/dist/v${required}/${topdir}.tar.gz" -o "${archive}"
  curl -fsSL --retry 2 "https://nodejs.org/dist/v${required}/SHASUMS256.txt" -o "${sums}"
  expected="$(awk -v f="${topdir}.tar.gz" '$2 == f {print $1; exit}' "${sums}")"
  actual="$(sha256sum "${archive}" | awk '{print $1}')"
  [[ -n "${expected}" && "${expected}" == "${actual}" ]] || {
    err "Node.js 工具链 SHA-256 校验失败"; exit 1;
  }
  mkdir -p "${TMP_DIR}/node-toolchain"
  tar -xzf "${archive}" -C "${TMP_DIR}/node-toolchain" --strip-components=1
  printf '%s\n' "${TMP_DIR}/node-toolchain/bin"
}

build_from_source() {
  local arch="$1" output="$2" ref="${SOURCE_REF}" source_dir go_required go_cmd node_bin goarch goarm="" build_version

  if [[ -n "${VERSION}" && "${VERSION}" != "latest" && "${VERSION}" != "stable" && "${SOURCE_REF}" == "main" ]]; then
    ref="${VERSION}"
  fi

  install_build_dependencies
  source_dir="${TMP_DIR}/source"
  log "未找到可用二进制，开始从 ${SOURCE_REPO}@${ref} 编译（首次通常需要数分钟）"
  if ! git clone --depth 1 --branch "${ref}" "https://github.com/${SOURCE_REPO}.git" "${source_dir}"; then
    err "无法取得源码分支/标签 ${SOURCE_REPO}@${ref}"
    exit 1
  fi

  go_required="$(awk '$1 == "go" {print $2; exit}' "${source_dir}/go.mod")"
  [[ -n "${go_required}" ]] || { err "go.mod 中没有 Go 版本"; exit 1; }
  go_cmd="$(prepare_go "${go_required}" "${arch}")"
  node_bin="$(prepare_node "${arch}")"

  log "构建 Web 前端"
  PATH="${node_bin}:${PATH}" npm ci --prefix "${source_dir}/web"
  PATH="${node_bin}:${PATH}" npm run build --prefix "${source_dir}/web"
  rm -rf "${source_dir}/internal/web/dist"
  mkdir -p "${source_dir}/internal/web"
  cp -R "${source_dir}/web/dist" "${source_dir}/internal/web/dist"

  case "${arch}" in
    amd64) goarch="amd64" ;;
    arm64) goarch="arm64" ;;
    armv7) goarch="arm"; goarm="7" ;;
  esac
  build_version="$(git -C "${source_dir}" describe --tags --always 2>/dev/null || git -C "${source_dir}" rev-parse --short HEAD)"
  log "构建 VoHive ${build_version} (${arch})"
  (
    cd "${source_dir}"
    GOWORK=off GOTOOLCHAIN=auto CGO_ENABLED=0 GOOS=linux GOARCH="${goarch}" GOARM="${goarm}" \
      "${go_cmd}" build -trimpath -buildvcs=false -tags "with_utls nomsgpack" \
      -ldflags "-s -w -X 'github.com/iniwex5/vohive/internal/global.Version=${build_version}' -X 'github.com/iniwex5/vohive/internal/global.BuildTime=$(date -u +'%Y-%m-%dT%H:%M:%SZ')'" \
      -o "${output}" ./cmd/vohive
  )
  is_elf "${output}" || { err "源码编译结果不是有效 ELF 二进制"; exit 1; }
  chmod 0755 "${output}"
  printf '%s\n' "${build_version} (source:${ref})" > "${TMP_DIR}/installed-version"
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
  run_root systemctl daemon-reload
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
    if [[ "${BINARY_ONLY}" == "1" ]]; then
      err "你的两个 fork 目前没有可用 Release 二进制。请去掉 --binary-only 允许自动源码编译。"
      exit 1
    fi
    build_from_source "${arch}" "${candidate}"
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
