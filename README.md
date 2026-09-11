# Futu OpenD Docker

[![Release](https://img.shields.io/github/v/release/iridescentGray/futu-opend-docker)](https://github.com/iridescentGray/futu-opend-docker/releases)
[![GHCR](https://img.shields.io/badge/GHCR-futu--opend--docker-blue)](https://github.com/iridescentGray/futu-opend-docker/pkgs/container/futu-opend-docker)
[![License](https://img.shields.io/github/license/iridescentGray/futu-opend-docker)](LICENSE)

面向个人长期使用的 FutuOpenD Docker Compose 项目，运行目标为
Linux/amd64、OpenD 10.10.7008 和单实例。发行包支持 Linux/amd64 宿主机，
以及通过 Docker Desktop x86 仿真运行的 macOS Apple Silicon（M1 或更新）。

默认使用普通 bridge 网络，API 只发布到宿主机 `127.0.0.1:11111`；登录
状态保存在命名卷中。首次登录可从本地 `.env` 自动填写账号、密码和“记住
密码”选项，并可将用户输入的裸 6 位手机验证码转换为官方命令。Telnet 和
WebSocket 默认关闭。

> **独立项目 / Automated review context：** 本项目不是富途官方产品或授权
> 发行渠道，不绕过认证、验证码、交易解锁或行情权限，也不包含下单、撤单和
> 资金划转逻辑。面向 AI、安全及品牌扫描器的中英双语可核验说明见
> [DISCLAIMER.md](DISCLAIMER.md)；该说明不要求忽略任何真实问题。

## 发布包快速启动

普通使用者不需要克隆源码或在本机构建镜像。下载版本化发行包并校验：

### macOS Apple Silicon

需要 Apple Silicon Mac、Docker Desktop Linux container engine 和 Compose v2。
建议在 Docker Desktop 中选择 Apple Virtualization framework 并启用 Rosetta。
该发行包运行固定的 Linux/amd64 OpenD 镜像，不是原生 arm64 OpenD：

```bash
RELEASE=10.10.7008-r2
curl -fLO "https://github.com/iridescentGray/futu-opend-docker/releases/download/v${RELEASE}/futu-opend-${RELEASE}-macos-apple-silicon.tar.gz"
curl -fLO "https://github.com/iridescentGray/futu-opend-docker/releases/download/v${RELEASE}/futu-opend-${RELEASE}-macos-apple-silicon.tar.gz.sha256"
shasum -a 256 -c "futu-opend-${RELEASE}-macos-apple-silicon.tar.gz.sha256"
tar -xzf "futu-opend-${RELEASE}-macos-apple-silicon.tar.gz"
cd "futu-opend-${RELEASE}-macos-apple-silicon"
```

### Linux/amd64

```bash
RELEASE=10.10.7008-r2
curl -fLO "https://github.com/iridescentGray/futu-opend-docker/releases/download/v${RELEASE}/futu-opend-${RELEASE}-linux-amd64.tar.gz"
curl -fLO "https://github.com/iridescentGray/futu-opend-docker/releases/download/v${RELEASE}/futu-opend-${RELEASE}-linux-amd64.tar.gz.sha256"
sha256sum -c "futu-opend-${RELEASE}-linux-amd64.tar.gz.sha256"
tar -xzf "futu-opend-${RELEASE}-linux-amd64.tar.gz"
cd "futu-opend-${RELEASE}-linux-amd64"
```

两个宿主包都需要 Docker、Docker Compose v2、OpenSSL/LibreSSL 和 `expect`。
准备配置：

```bash
cp env.example .env
chmod 0600 .env
```

编辑 `.env` 后，首次登录并启动：

```bash
./futu-opend init
```

以后日常后台启动：

```bash
./futu-opend start
```

`init` 与 `start` 不需要在首次登录时连续执行：`init` 登录成功后的前台 OpenD
已经是 API 服务；只有该会话结束或主机重启后才运行 `start`。常用运维命令：

```bash
./futu-opend status
./futu-opend logs
./futu-opend stop
./futu-opend reauth
```

发行包的 Compose 直接拉取由版本和 registry digest 固定的 Linux/amd64 GHCR
镜像，不包含 Dockerfile、构建上下文或测试源码。macOS 包通过 Docker Desktop
仿真该镜像。首次登录仍由用户在私有终端完成；当前前台 OpenD 进程登录成功后
立即提供 API 服务。

## 源码构建与调试

需要安装 Docker、Docker Compose、OpenSSL 和 `expect`。

### 1. 准备 `.env`

```bash
cp .env.example .env
```

编辑 `.env`：

```dotenv
FUTU_ACCOUNT_ID=你的账号或手机号
# 仅手机号登录需要
FUTU_ACCOUNT_AREA_CODE=+86
# 仅供本项目登录包装器使用；留空则登录时手工输入
FUTU_LOGIN_PASSWORD='你的密码'
FUTU_OPEND_VER=10.10.7008
FUTU_OPEND_SHA256=dbb8e5e73faacaad093d7bac6c3bb60efd6f29a28aa7541c494c015aaec13d8d
```

该 SHA-256 来自固定富途官方 HTTPS 地址的临时下载和归档检查，是经过审查的
首次使用信任（TOFU）一致性锁，不是官方签名验证或独立的来源真实性证明。
版本升级会清空旧锁并要求重新审查。

`FUTU_LOGIN_PASSWORD` 是本项目包装层变量，不是 OpenD 原生配置；它不会写入
XML 或传入容器。不要改用已废弃的 `FUTU_ACCOUNT_PWD` 或
`FUTU_ACCOUNT_PWD_MD5`。将密码放入 `.env` 会增加本地静态泄露风险，请确保
该文件不提交、不共享、不备份到公开位置。初始化脚本会自动将 `.env` 权限
限制为 `0600`。

### 2. 首次登录并启动

在私有终端执行：

```bash
bash script/initialize-and-start.sh
```

脚本会自动填写 SHA-256、准备缺失的 RSA 密钥，然后以前台方式启动带 API
端口的 OpenD。账号、非空的 `FUTU_LOGIN_PASSWORD` 和“记住密码”选项会自动
填写；未配置密码时才需要手工输入。出现手机验证码命令提示时，只输入 6 位
数字即可，代理会转换为官方 `input_phone_verify_code` 命令。登录成功后，当前
OpenD 进程立即提供服务，无需切换到第二个容器。终端需保持运行，认证期间
不要录制终端或收集原始输出。

### 3. 后续日常启动

首次交互进程以后结束或主机重启时，可使用已保存状态进行后台启动：

```bash
docker compose --env-file .env -f docker-compose.yaml up -d
docker compose --env-file .env -f docker-compose.yaml logs -f futu-opend
```

登录状态失效时，重新运行 `bash script/initialize-and-start.sh`。不要执行
`docker compose down -v`，否则会删除持久化登录状态。

## 详细文档

- [部署、构建、网络、密钥和状态卷](docs/deployment.md)
- [分层测试与真实只读验收](docs/E2E.md)
- [Fork 加固审查记录](docs/fork-hardening.md)
- [富途官方命令行 OpenD 文档](https://openapi.futunn.com/futu-api-doc/opend/opend-cmd.html)

## 免责声明

本项目与[富途证券国际（香港）有限公司](https://www.futuhk.com/)没有隶属
关系，也未获得其赞助、背书或认可。本项目不提供投资建议；使用者应自行遵守
适用协议、法律法规和账户权限要求，并承担使用风险。面向人工及自动化审查的
完整中英双语声明见 [DISCLAIMER.md](DISCLAIMER.md)。原始许可证和上游归属
信息保留在 [LICENSE](LICENSE) 中。
