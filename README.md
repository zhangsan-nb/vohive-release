# VoHive 私有发布仓库

本仓库用于个人内部测试环境中的 VoHive 二进制、安装脚本和运维说明。仓库改为私有后，安装脚本和 Release 必须使用 GitHub fine-grained personal access token 下载。

> [!WARNING]
> 仅供个人学习、研究和内部测试。不要把长期 Token、源码或二进制交给不受你控制的设备或其他人。

## 1. 支持环境

推荐 Debian、Ubuntu 或其他带 systemd 的 Linux。预编译二进制支持 `amd64`、`arm64` 和 `armv7`，安装器会自动识别 CPU 架构。

# Debian / Ubuntu 私有一键部署

## 2. 创建 GitHub fine-grained Token

进入 GitHub：

```text
Settings
→ Developer settings
→ Personal