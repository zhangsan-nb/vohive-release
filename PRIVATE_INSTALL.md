# 私有仓库一键安装

适用于 `zhangsan-nb/vohive-release` 和 `zhangsan-nb/vohive` 改为私有后的安装与更新。

## Token 权限

Fine-grained personal access token 只需要：

- Repository access：仅 `vohive-release`、`vohive`
- Contents：Read-only
- Metadata：Read-only（GitHub 自动要求）

不要把 Token 提交到仓库、写入 VoHive 配置或 Docker 镜像。

## 首次安装

在目标 Linux 机器执行：

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

Token 只用于本次下载。安装后的 VoHive 二进制和 `config.yaml` 中不会保存 Token。

## 安装指定版本

```bash
sudo env VOHIVE_GITHUB_TOKEN="${TOKEN}" \
  bash /tmp/vohive-install.sh --version v1.5.5-10-gf9eb85d
```

## 后续更新

重新执行“首次安装”命令即可。安装器会：

1. 查询私有仓库的 latest Release；
2. 自动识别 amd64、arm64 或 armv7；
3. 通过 GitHub API 鉴权下载对应二进制；
4. 对已知版本校验 SHA-256；
5. 备份旧二进制；
6. 保留现有配置和数据；
7. 重启 systemd 服务；
8. 新版本启动失败时尝试恢复旧二进制。

## 不使用环境变量

安装器也支持从终端隐藏输入 Token。下载脚本后直接执行：

```bash
sudo bash /tmp/vohive-install.sh
```

脚本会显示 `GitHub Token:`，输入时不会回显。

也可以使用仅 root 可读的临时 Token 文件：

```bash
sudo bash /tmp/vohive-install.sh --token-file /root/vohive-token
```

用完后删除该文件：

```bash
sudo rm -f /root/vohive-token
```

## 注意

- `No expiration` 仅表示没有预设到期日；Token 仍可被你手动撤销或因安全原因失效。
- Token 持有者在有效期内可以读取被授权的两个私有仓库。
- 不建议将长期 Token 交给不受你控制的电脑或其他人。
- 已经安装并运行的 VoHive 不依赖 GitHub；Token 失效只会影响后续安装和更新。
