# Futu OpenD Docker

[![Docker Pulls](https://img.shields.io/github/package-json/v/manhinhang/futu-opend-docker)](https://github.com/manhinhang/futu-opend-docker/packages)
[![GitHub](https://img.shields.io/github/license/manhinhang/futu-opend-docker)](https://github.com/manhinhang/futu-opend-docker/blob/main/LICENSE)

面向个人长期使用的 FutuOpenD Docker Compose 项目，主要支持
Linux/amd64、OpenD 10.10.7008 和单实例运行。

默认使用普通 bridge 网络，API 只发布到宿主机 `127.0.0.1:11111`；登录
状态保存在命名卷中。项目不会自动输入密码或验证码，Telnet 和 WebSocket
默认关闭。

## 快速启动

需要安装 Docker、Docker Compose 和 OpenSSL。

### 1. 准备 `.env`

```bash
cp .env.example .env
```

编辑 `.env`：

```dotenv
FUTU_ACCOUNT_ID=你的账号或手机号
# 仅手机号登录需要
FUTU_ACCOUNT_AREA_CODE=+86
FUTU_OPEND_VER=10.10.7008
FUTU_OPEND_SHA256=
```

首次启动时，如果 SHA-256 为空，脚本会从固定的富途官方 HTTPS 地址临时
下载并检查安装包，然后自动将候选摘要写入本地 `.env`。这是首次使用信任
（TOFU），不是官方签名验证或独立的来源真实性证明。

不要设置 `FUTU_ACCOUNT_PWD` 或 `FUTU_ACCOUNT_PWD_MD5`。

### 2. 首次登录并启动

在私有终端执行：

```bash
bash script/initialize-and-start.sh
```

脚本会自动填写 SHA-256、准备缺失的 RSA 密钥，然后以前台方式启动带 API
端口的 OpenD。接下来只需要完成富途官方登录提示；官方仍可能要求账号、
密码、记住密码选择或验证码。登录成功后，当前 OpenD 进程立即提供服务，
无需输入本项目额外的确认词，也无需切换到第二个容器。终端需保持运行。

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
关系。原始许可证和上游归属信息保留在 [LICENSE](LICENSE) 中。
