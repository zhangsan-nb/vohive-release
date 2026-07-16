# VoHive 私有发布仓库

本仓库用于个人内部测试环境中的 VoHive 二进制、安装脚本和运维说明。仓库改为私有后，安装脚本和 Release 必须使用 GitHub fine-grained personal access token 下载。

> [!WARNING]
> 仅供个人学习、研究和内部测试。不要把长期 Token、源码或二进制交给不受你控制的设备或其他人。

## 支持环境

推荐 Debian、Ubuntu 或其他带 systemd 的 Linux。预编译二进制支持 `amd64`、`arm64` 和 `armv7`，安装器会自动识别 CPU 架构。

# Debian / Ubuntu 私有一键部署

## 1. 旧版无需卸载

已经安装在 `/opt/vohive` 的旧版本可以直接原地升级。安装器会保留：

- `/opt/vohive/config/config.yaml`
- `/opt/vohive/data`
- `/opt/vohive/logs`

旧二进制会备份为 `/opt/vohive/bin/vohive.bak`。只有确定要永久删除配置、数据库、短信记录和日志时，才使用彻底卸载。

## 2. 安装依赖

root 用户直接执行：

```bash
apt-get update
apt-get install -y curl ca-certificates python3
```

普通用户先执行 `su -` 切换到 root，或在命令前添加 `sudo`。

## 3. 第一次保存 GitHub Token

由于部分网页终端无法使用 `read -s` 输入 Token，推荐保存到仅 root 可读的文件。

先执行：

```bash
install -d -m 700 /root/.config/vohive
umask 077
cat > /root/.config/vohive/github-token
```

终端停住后：

1. 粘贴 GitHub Token；
2. 按一次回车；
3. 按 `Ctrl+D` 结束输入。

然后执行：

```bash
chmod 600 /root/.config/vohive/github-token
TOKEN_LENGTH="$(tr -d '\r\n' < /root/.config/vohive/github-token | wc -c)"
echo "Token 文件已保存，长度：${TOKEN_LENGTH}"
```

不要运行 `cat /root/.config/vohive/github-token`，也不要把 Token 发到聊天、截图或提交到仓库。

Token 权限只需要：

- Repository access：`vohive-release`、`vohive`
- Contents：Read-only
- Metadata：Read-only

## 4. 新装或原地升级

复制执行下面整段命令：

```bash
set -e

TOKEN_FILE=/root/.config/vohive/github-token
CURL_CONFIG="$(mktemp)"
INSTALLER="$(mktemp)"

cleanup() {
  rm -f "${CURL_CONFIG}" "${INSTALLER}"
}
trap cleanup EXIT

[[ -s "${TOKEN_FILE}" ]] || {
  echo "Token 文件不存在或为空：${TOKEN_FILE}" >&2
  exit 1
}

{
  printf 'header = "Authorization: Bearer '
  tr -d '\r\n' < "${TOKEN_FILE}"
  printf '"\n'
  printf '%s\n' \
    'header = "Accept: application/vnd.github.raw+json"' \
    'header = "X-GitHub-Api-Version: 2022-11-28"'
} > "${CURL_CONFIG}"

chmod 600 "${CURL_CONFIG}"

curl -fsSL \
  --config "${CURL_CONFIG}" \
  "https://api.github.com/repos/zhangsan-nb/vohive-release/contents/install-private.sh?ref=master" \
  -o "${INSTALLER}"

bash "${INSTALLER}" --token-file "${TOKEN_FILE}"
```

这条命令既适用于全新 Debian，也适用于已经安装旧版 VoHive 的机器。

## 5. 安装完成后检查

```bash
systemctl status vohive --no-pager
journalctl -u vohive -n 50 --no-pager
hostname -I
```

浏览器访问：

```text
http://服务器局域网IP:7575
```

## 6. 安装一键更新命令

首次安装成功后，可以创建 `/usr/local/sbin/vohive-update`：

```bash
cat > /usr/local/sbin/vohive-update <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

TOKEN_FILE=/root/.config/vohive/github-token
CURL_CONFIG="$(mktemp)"
INSTALLER="$(mktemp)"

cleanup() {
  rm -f "${CURL_CONFIG}" "${INSTALLER}"
}
trap cleanup EXIT

[[ -s "${TOKEN_FILE}" ]] || {
  echo "Token 文件不存在或为空：${TOKEN_FILE}" >&2
  exit 1
}

{
  printf 'header = "Authorization: Bearer '
  tr -d '\r\n' < "${TOKEN_FILE}"
  printf '"\n'
  printf '%s\n' \
    'header = "Accept: application/vnd.github.raw+json"' \
    'header = "X-GitHub-Api-Version: 2022-11-28"'
} > "${CURL_CONFIG}"

chmod 600 "${CURL_CONFIG}"

curl -fsSL \
  --config "${CURL_CONFIG}" \
  "https://api.github.com/repos/zhangsan-nb/vohive-release/contents/install-private.sh?ref=master" \
  -o "${INSTALLER}"

bash "${INSTALLER}" --token-file "${TOKEN_FILE}" "$@"
SCRIPT

chmod 700 /usr/local/sbin/vohive-update
```

以后安装最新版本或更新只需执行：

```bash
vohive-update
```

安装指定版本：

```bash
vohive-update --version v1.5.5-10-gf9eb85d
```

普通更新不要使用 `--force-config`，否则会备份原配置并生成新的随机 Web 密码。

# 备份

```bash
systemctl stop vohive
tar -C /opt -czf "/root/vohive-backup-$(date +%Y%m%d-%H%M%S).tar.gz" \
  vohive/config vohive/data
systemctl start vohive
```

# 卸载

先使用 Token 下载卸载脚本：

```bash
TOKEN_FILE=/root/.config/vohive/github-token
CURL_CONFIG="$(mktemp)"

{
  printf 'header = "Authorization: Bearer '
  tr -d '\r\n' < "${TOKEN_FILE}"
  printf '"\n'
  printf '%s\n' \
    'header = "Accept: application/vnd.github.raw+json"' \
    'header = "X-GitHub-Api-Version: 2022-11-28"'
} > "${CURL_CONFIG}"

chmod 600 "${CURL_CONFIG}"

curl -fsSL \
  --config "${CURL_CONFIG}" \
  "https://api.github.com/repos/zhangsan-nb/vohive-release/contents/uninstall.sh?ref=master" \
  -o /tmp/vohive-uninstall.sh

rm -f "${CURL_CONFIG}"
```

普通卸载，保留配置和数据：

```bash
bash /tmp/vohive-uninstall.sh
rm -f /tmp/vohive-uninstall.sh
```

彻底卸载全部数据：

> [!CAUTION]
> 下面的命令会永久删除配置、数据库、短信记录和日志，无法恢复。

```bash
bash /tmp/vohive-uninstall.sh --purge
rm -f /tmp/vohive-uninstall.sh
```

# 默认目录

- 二进制：`/opt/vohive/bin/vohive`
- 配置：`/opt/vohive/config/config.yaml`
- 数据：`/opt/vohive/data`
- 日志：`/opt/vohive/logs`
- Token：`/root/.config/vohive/github-token`
- systemd 服务：`/etc/systemd/system/vohive.service`

# Docker 状态

仓库私有后，旧 Dockerfile 匿名下载公开 Release 的方式会失效。当前建议使用 Debian/Ubuntu 原生部署。Docker 私有构建必须使用 BuildKit secret 临时传入 Token，不能通过 `ARG`、`ENV` 或直接写入镜像。