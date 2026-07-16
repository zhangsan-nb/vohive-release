# VoHive 私有发布仓库

本仓库用于个人内部测试环境中的 VoHive 二进制、安装脚本和运维说明。仓库改成私有后，安装脚本和 Release 必须使用 GitHub fine-grained personal access token 下载。

> [!WARNING]
> 仅供个人学习、研究和内部测试。不要把长期 Token、源码或二进制交给不受你控制的设备或其他人。

## 支持环境

推荐 Debian、Ubuntu 或其他带 systemd 的 Linux。预编译二进制支持 `amd64`、`arm64` 和 `armv7`，安装器会自动识别 CPU 架构。

# Debian / Ubuntu 私有一键部署

## 已经安装旧版：不要先卸载

旧版已经安装在 `/opt/vohive` 时，可以直接执行下面的私有安装命令进行**原地升级**。安装器会：

- 保留 `/opt/vohive/config/config.yaml`
- 保留 `/opt/vohive/data`
- 保留 `/opt/vohive/logs`
- 把旧二进制备份为 `/opt/vohive/bin/vohive.bak`
- 安装新二进制并重启 `vohive.service`
- 新版本启动失败时尝试恢复旧二进制

只有准备永久删除配置、数据库、短信记录和日志时，才使用彻底卸载。

## 安装依赖

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates python3
```

## 首次切换到私有安装器

输入 Token 时终端不会显示字符：

```bash
read -rsp "GitHub Token: " TOKEN
echo

curl -fsSL \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/zhangsan-nb/vohive-release/contents/install-private.sh?ref=master" \
  -o /tmp/vohive-install.sh

sudo env VOHIVE_GITHUB_TOKEN="${TOKEN}" \
  bash /tmp/vohive-install.sh

unset TOKEN
rm -f /tmp/vohive-install.sh
```

Token 只在本次下载和安装期间使用，不会写入 VoHive 二进制或 `/opt/vohive/config/config.yaml`。

## 后续更新

重新执行上面的命令即可；配置、数据库和日志都会保留。

指定版本：

```bash
sudo env VOHIVE_GITHUB_TOKEN="${TOKEN}" \
  bash /tmp/vohive-install.sh --version v1.5.5-10-gf9eb85d
```

普通更新不要使用 `--force-config`，否则会备份旧配置并生成新的随机 Web 密码。

## 安装完成后检查

```bash
systemctl status vohive --no-pager
journalctl -u vohive -n 50 --no-pager
hostname -I
```

浏览器访问：

```text
http://服务器局域网IP:7575
```

# 备份（可选）

原地升级通常不需要手动备份。需要额外快照时：

```bash
sudo systemctl stop vohive
sudo tar -C /opt -czf "/root/vohive-backup-$(date +%Y%m%d-%H%M%S).tar.gz" \
  vohive/config vohive/data
sudo systemctl start vohive
```

# 卸载

仓库私有后，不能再使用匿名的 `raw.githubusercontent.com/.../uninstall.sh | bash`。需要卸载时，先用 Token 下载脚本：

```bash
read -rsp "GitHub Token: " TOKEN
echo

curl -fsSL \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Accept: application/vnd.github.raw+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/zhangsan-nb/vohive-release/contents/uninstall.sh?ref=master" \
  -o /tmp/vohive-uninstall.sh

unset TOKEN
```

## 普通卸载：保留配置和数据

```bash
sudo bash /tmp/vohive-uninstall.sh
rm -f /tmp/vohive-uninstall.sh
```

## 彻底卸载：删除全部数据

> [!CAUTION]
> 下列命令会永久删除配置、数据库、短信记录和日志，无法恢复。

```bash
sudo bash /tmp/vohive-uninstall.sh --purge
rm -f /tmp/vohive-uninstall.sh
```

# 默认目录

- 二进制：`/opt/vohive/bin/vohive`
- 配置：`/opt/vohive/config/config.yaml`
- 数据：`/opt/vohive/data`
- 日志：`/opt/vohive/logs`
- systemd 服务：`/etc/systemd/system/vohive.service`

# Docker 状态

仓库私有后，旧 Dockerfile 中匿名下载公开 Release 的方式会失效。当前建议先使用上面的 Debian/Ubuntu 原生部署。Docker 私有部署需要用 BuildKit secret 临时传入 Token，不能通过 `ARG`、`ENV` 或写进镜像。