# GitHub Token 创建教程（1—5 步）

> Token 等同密码。不要把生成后的 Token 发到聊天、截图、仓库或不受你控制的设备。

进入 GitHub：

```text
Settings
→ Developer settings
→ Personal access tokens
→ Fine-grained tokens
→ Generate new token
```

## 1. 设置名称、所有者和有效期

填写：

```text
Token name: vohive-install
Resource owner: zhangsan-nb
Expiration: No expiration
```

`No expiration` 表示没有预设到期时间，但 Token 仍可能因手动撤销、泄露、安全原因或账号权限变化而失效。

## 2. 只选择两个仓库

在 `Repository access` 中选择：

```text
Only select repositories
```

然后勾选：

```text
✓ zhangsan-nb/vohive
✓ zhangsan-nb/vohive-release
```

不要选择 `All repositories`。

## 3. 添加 Contents 权限

在 `Permissions` 区域右侧点击：

```text
+ Add permissions
```

然后：

1. 选择或搜索 `Contents`；
2. 点击添加；
3. 将 `Contents` 设置为 `Read-only`。

`Contents: Read-only` 足以读取私有仓库文件、分支、源码和 Release 资产，不需要写权限。

## 4. 保留 Metadata，只读即可

GitHub 会自动添加：

```text
Metadata: Read-only
```

这是必需权限，保留即可。其他权限全部保持 `No access`。

最终应显示：

```text
Repositories 2
Contents        Read-only
Metadata        Read-only
```

## 5. 生成并保存 Token

确认页面显示：

```text
Expiration: No expiration
Repository access: Only select repositories
Contents: Read-only
Metadata: Read-only
```

然后点击：

```text
Generate token
```

Token 只会完整显示一次，请立即复制并安全保存。

## Token 更换后

创建新 Token 后，只需要覆盖 Debian 上的 Token 文件：

```bash
cat > /root/.config/vohive/github-token
```

粘贴新 Token，按一次回车，再按 `Ctrl+D`，然后执行：

```bash
chmod 600 /root/.config/vohive/github-token
vohive-update
```

无需卸载或重装 VoHive。旧 Token 应在 GitHub 中撤销。
