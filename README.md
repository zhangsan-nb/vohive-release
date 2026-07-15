# VoHive Release

公开分发仓库：提供二进制发布资产、安装脚本和运维文档。

# 项目源码（当前维护 Fork）
https://github.com/zhangsan-nb/vohive

## 免责声明

> [!WARNING]
> **重要提示：本软件（VoHive）仅供个人内部测试使用，严禁商业使用，以及严禁将本软件用于任何非法或违规场景。**
> 
> 使用者因违反当地法律法规、非法使用本软件造成的一切法律责任及后果，由使用者自行承担，软件原作者不承担任何责任。使用本软件即表示您同意本免责声明。

## 功能介绍

VoHive 是面向高通 4G/5G 模组场景的一体化测试平台，核心能力包括：

- 网页/Bot收发短信
- 多卡统一管理
- 实体 ESIM/eUICC 管理（加卡，切卡，删卡）
- TelegramBot / 飞书Bot / QQBot
- 在条件满足时启用 VoWiFi测试
- 通过 `/vocall` 发起 VoWiFi 模拟外呼测试

## 一、适用环境

### 硬件

推荐：

- 移远 EC20CE 系4G模块
- 移远 EM500Q 5G模块
- 高通 410 WIFI板子(得debian/openwrt,需要有折腾能力)
- 以及各类高通4G USB模组
- 可以小黄鱼几十块买到

要求：

- 设备具备 SIM 卡槽
- 或搭配带SIM卡槽的USB底板

### 系统

建议使用 Linux：

- Debian / Ubuntu
- 树莓派
- NAS

## 二、ModemManager 共存说明

VoHive 在 QMI 模式下会优先通过 `qmi-proxy` 打开控制口，可与系统 `ModemManager` 共用 QMI 通道。

注意：  
同时运行两个管理方时，不建议让两边同时管理拨号、APN 或数据连接。

## 三、可选：把模组切到更合适的 USBNET 模式

如果你确认模组当前模式不对，可以执行：

```bash
sudo apt update
sudo apt install -y socat

echo 'AT+QCFG="usbnet",0;+CFUN=1,1' | sudo socat - /dev/ttyUSB2,crnl
```

说明：

- `AT+QCFG="usbnet",0`：切到常见的 QMI 模式
- `AT+CFUN=1,1`：重启模组
- `/dev/ttyUSB2` 只是示例，实际 AT 口请按你的设备调整

## 四、部署方式一：一键安装

目前提供以下 Linux 架构的预编译二进制：

- `amd64`：普通 Intel/AMD 64 位电脑、服务器和虚拟机
- `arm64`：64 位 ARM 设备
- `armv7`：32 位 ARM 设备

安装脚本会自动识别 CPU 架构、下载对应二进制，并校验 SHA-256。

### 4.1 Debian / Ubuntu：root 用户安装

如果终端提示符类似 `root@debian:~#`，说明当前就是 root 用户。

先安装下载工具：

```bash
apt-get update
apt-get install -y curl ca-certificates
```

然后一键安装：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | bash
```

### 4.2 Debian / Ubuntu：普通用户安装

普通用户需要使用 `sudo`：

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates
```

然后安装：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | sudo bash
```

### 4.3 安装指定版本

root 用户执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | bash -s -- --version v1.5.5-10-gf9eb85d
```

普通用户执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | sudo bash -s -- --version v1.5.5-10-gf9eb85d
```

### 4.4 安装完成后检查

查看服务状态：

```bash
systemctl status vohive --no-pager
```

查看最近日志：

```bash
journalctl -u vohive -n 50 --no-pager
```

持续查看实时日志：

```bash
journalctl -u vohive -f
```

查询服务器局域网 IP：

```bash
hostname -I
```

浏览器访问：

```text
http://服务器局域网IP:7575
```

首次安装会在终端显示：

- Web 用户名
- 自动生成的随机密码
- 可访问的后台地址

请立即保存随机密码，不要将 `7575` 端口直接开放到公网。

### 4.5 更新或重新安装

再次执行安装命令即可。安装脚本会：

- 保留现有配置和数据
- 将旧二进制备份为 `/opt/vohive/bin/vohive.bak`
- 下载并校验新二进制
- 重启 VoHive 服务
- 启动失败时尝试恢复旧二进制

root 用户执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | bash
```

### 4.6 普通卸载：保留配置和数据

普通卸载会删除程序和 systemd 服务，但保留配置、数据库和日志，方便以后重新安装。

root 用户执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/uninstall.sh \
  | bash
```

### 4.7 彻底卸载：删除全部数据

> [!CAUTION]
> 下面的命令会永久删除 VoHive 程序、配置、数据库、短信记录和日志，无法恢复。

root 用户执行：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/uninstall.sh \
  | bash -s -- --purge
```

卸载后确认：

```bash
test -e /opt/vohive \
  && echo "仍有残留" \
  || echo "VoHive 已全部删除"
```

### 4.8 不使用 systemd 的高级安装方式

普通 Debian/Ubuntu 用户不需要使用此方式。

仅适用于容器、部分 NAS 或没有 systemd 的 Linux：

```bash
curl -fsSL \
  https://raw.githubusercontent.com/zhangsan-nb/vohive-release/master/install.sh \
  | bash -s -- --no-systemd
```

安装后需要手动启动：

```bash
cd /opt/vohive
./bin/vohive -c ./config/config.yaml
```


## 默认安装目录（便携部署）

- 二进制：`/opt/vohive/bin/vohive`
- 配置：`/opt/vohive/config/config.yaml`
- 数据：`/opt/vohive/data`
- 日志目录：`/opt/vohive/logs`


## 五、部署方式二：Docker / Docker Compose

### 1. 创建目录

```bash
mkdir -p vohive/{config,data,logs}
cd vohive
```

### 2. 创建配置文件

新建 `config/config.yaml`：

```yaml
server:
  port: 7575
  debug: false

web:
  username: admin
  password: admin123
```

### 3. 创建 `docker-compose.yml`

```yaml
services:
  vohive:
    image: iniwex/vohive:latest
    container_name: vohive
    restart: unless-stopped
    network_mode: host
    privileged: true
    volumes:
      - ./config:/app/config
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - TZ=Asia/Shanghai
      - CONFIG_PATH=/app/config/config.yaml
    devices:
      - /dev:/dev
```

### 4. 启动

```bash
docker compose up -d
```


### 5. 访问后台

```text
http://你的服务器IP:7575
```
注意：

- Docker 部署下AT模式也要关闭宿主机 `ModemManager`
- 这里用了 `privileged`、`/dev` 透传和 `host network`，这是因为程序需要直接接管模组设备

## 六、机器人常用命令

- `/list`：查看设备列表
- `/sms 设备ID`：查看最近短信
- `/send 设备ID 号码 内容`：发送短信
- `/rotate 设备ID`：切换 IP
- `/esim 设备ID`：查看 eSIM profile
- `/switch 设备ID 序号或 ICCID`：切换 eSIM profile
- `/vocall 设备ID 号码`：发起 VoWiFi 模拟呼叫

## 七、补充说明

- VoWiFi 不是只要有网就一定能用，还取决于运营商、号码状态和网络环境要求
- 如果你的需求只是短信、代理池、多模组管理，不折腾 VoWiFi 也可以先用起来
- 本程序已禁止国内运营商卡发起VoWifi，请遵纪守法。
## 八、已知Vohive支持VoWifi的运营商

- CTE UK
- CMLINK UK
- giffgaff UK
- VOXI UK
- Vodafone UK
- 3UK

- Vodafone DE
- Telekom DE
- O2 DE

- T-Mobile US
- RedPocket US
- Lyca US
- AT&T US
- 未标出的不代表不兼容，只是我没有
### 程序截图

![image](https://cdn.nodeimage.com/i/rnGhjMfPlMatrdxQMPogawI3d5OGc1Fu.png)

![image](https://cdn.nodeimage.com/i/GGAj5ua1dK4vZihroXV0pUmT7COonPnQ.png)

![image](https://cdn.nodeimage.com/i/hX90MLQqjmgkaPkZt4Pz4uCM1lHmDBx4.png)

![image](https://cdn.nodeimage.com/i/jbbwBuP1Zu9iPpfZrSsXzftGo0et5i4F.png)

![image](https://cdn.nodeimage.com/i/P7BpZu8fF98622Q3VCZlafg4aBHVM8Qu.png)

![image](https://cdn.nodeimage.com/i/X5Ps5w9AHo1Qas6DDsnxYnbrfYcVhAfV.png)

### 发布频道：

https://t.me/vohive_channel

### 交流群：

https://t.me/vohive
