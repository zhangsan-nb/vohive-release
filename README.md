# VoHive 私有发布仓库

本仓库用于个人内部测试环境中的 VoHive 二进制、安装脚本和运维说明。私有仓库的脚本和 Release 必须使用 GitHub fine-grained personal access token 下载。

> [!WARNING]
> 仅供个人学习、研究和内部测试。Token 等同密码，不要发送到聊天、截图、仓库或不受你控制的设备。

## 支持环境

推荐 Debian、Ubuntu 或其他带 systemd 的 Linux。预编译二进制支持 `amd64`、`arm64` 和 `armv7`。

# 一、创建 GitHub Token

进入：

```text
GitHub Settings
→ Developer settings
→ Personal access tokens
→ Fine-grained tokens
→ Generate new token
```

按下面设置：

```text
Token name: vohive-install
Resource owner: zhangsan-nb
Expiration: No expiration
Repository access: Only select repositories
  ✓ zhangsan-nb/vohive
  ✓ zhangsan-nb/vohive-release
Repository permissions:
  Contents: Read-only
  Metadata: Read-only（自动要求）
```

操作步骤：

1. `Expiration` 选择 `No expiration`。
2. `Repository access` 选择 `Only select repositories`。
3. 选择 `vohive` 和 `vohive-release`。
4. 点击 `Add permissions`，添加 `Contents`。
5. 将 `Contents` 设为 `Read-only`。
6. 保留自动添加的 `Metadata: Read-only`。
7. 其他权限保持 `No access`。
8. 点击 `Generate token`，立即复制并安全保存。

`No expiration` 只是没有预定到期日。Token 仍可能因手动撤销、泄露、安全原因或账号权限变化而失效。已经运行的 VoHive 不依赖 Token；Token 失效只影响后续安装和更新。

# 二、旧版是否需要卸载

不需要。已经安装在 `/opt/vohive` 的旧版可以直接原地升级，并保留：

- `/opt/vohive/config/config.yaml`
- `/opt/vohive/data`
- `/opt/vohive/logs`

旧二进制会备份为 `/opt/vohive/bin/vohive.bak`。

# 三、新装 Debian 或原地升级

以下命令以 root 用户执行。提示符是 `root@debian:~#` 时不要使用 `sudo`。

## 1. 安装依赖

```bash
apt-get update
apt-get install -y curl ca-certificates python3
```

## 2. 第一次保存 Token

部分网页终端无法使用 `read -s`，推荐写入仅 root 可读的文件：

```bash
install -d -m 700 /root/.config/vohive
umask 077
cat > /root/.config/vohive/github-token
```

终端停住后：粘贴 Token，按一次回车，再按 `Ctrl+D`。

```bash
chmod 600 /root/.config/vohive/github-token
TOKEN_LENGTH="$(tr -d '\r\n' < /root/.config/vohive/github-token | wc -c)"
echo "Token 文件已保存，长度：${TOKEN_LENGTH}"
```

不要执行 `cat /root/.config/vohive/github-token`，避免显示 Token。

## 3. 一键安装

```bash
set -e
TOKEN_FILE=/root/.config/vohive/github-token
CURL_CONFIG="$(mktemp)"
INSTALLER="$(mktemp)"
trap 'rm -f "$CURL_CONFIG" "$INSTALLER"' EXIT

[[ -s "$TOKEN_FILE" ]] || { echo "Token 文件不存在或为空" >&2; exit 1; }

{
  printf 'header = "Authorization: Bearer '
  tr -d '\r\n' < "$TOKEN_FILE"
  printf '"\n'
  printf '%s\n' \
    'header = "Accept: application/vnd.github.raw+json"' \
    'header = "X-GitHub-Api-Version: 2022-11-28"'
} > "$CURL_CONFIG"
chmod 600 "$CURL_CONFIG"

curl -fsSL --config "$CURL_CONFIG" \
  'https://api.github.com/repos/zhangsan-nb/vohive-release/contents/install-private.sh?ref=master' \
  -o "$INSTALLER"

bash "$INSTALLER" --token-file "$TOKEN_FILE"
```

## 4. 检查服务

```bash
systemctl status vohive --no-pager
journalctl -u vohive -n 50 --no-pager
hostname -I
```

浏览器访问：

```text
http://服务器局域网IP:7575
```

# 四、安装后的一键更新

创建更新命令：

```bash
cat > /usr/local/sbin/vohive-update <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail
TOKEN_FILE=/root/.config/vohive/github-token
CURL_CONFIG="$(mktemp)"
INSTALLER="$(mktemp)"
trap 'rm -f "$CURL_CONFIG" "$INSTALLER"' EXIT
[[ -s "$TOKEN_FILE" ]] || { echo "Token 文件不存在或为空" >&2; exit 1; }
{
  printf 'header = "Authorization: Bearer '
  tr -d '\r\n' < "$TOKEN_FILE"
  printf '"\n'
  printf '%s\n' \
    'header = "Accept: application/vnd.github.raw+json"' \
    'header = "X-GitHub-Api-Version: 2022-11-28"'
} > "$CURL_CONFIG"
chmod 600 "$CURL_CONFIG"
curl -fsSL --config "$CURL_CONFIG" \
  'https://api.github.com/repos/zhangsan-nb/vohive-release/contents/install-private.sh?ref=master' \
  -o "$INSTALLER"
bash "$INSTALLER" --token-file "$TOKEN_FILE" "$@"
SCRIPT
chmod 700 /usr/local/sbin/vohive-update
```

以后更新最新版本：

```bash
vohive-update
```

指定版本：

```bash
vohive-update --version v1.5.5-10-gf9eb85d
```

普通更新不要使用 `--force-config`。

# 五、Token 更换或失效

创建新 Token 后，只需要覆盖 Token 文件：

```bash
cat > /root/.config/vohive/github-token
```

粘贴新 Token，按回车，再按 `Ctrl+D`，然后执行：

```bash
chmod 600 /root/.config/vohive/github-token
vohive-update
```

旧 Token 应在 GitHub 中撤销。无需重装 VoHive，也无需修改配置或二进制。

# 六、备份

```bash
systemctl stop vohive
tar -C /opt -czf "/root/vohive-backup-$(date +%Y%m%d-%H%M%S).tar.gz" \
  vohive/config vohive/data
systemctl start vohive
```

# 七、默认目录

- 二进制：`/opt/vohive/bin/vohive`
- 配置：`/opt/vohive/config/config.yaml`
- 数据：`/opt/vohive/data`
- 日志：`/opt/vohive/logs`
- Token：`/root/.config/vohive/github-token`
- 服务：`/etc/systemd/system/vohive.service`

# 八、Docker 状态

私有仓库下，旧 Dockerfile 的匿名 Release 下载方式会失效。当前建议使用上述 Debian/Ubuntu 原生部署。Docker 私有构建必须使用 BuildKit secret 临时传入 Token，不能通过 `ARG`、`ENV` 或直接写入镜像。