# 部署与运维详解

本文保存 FutuOpenD Docker 项目的构建锁定、登录、密钥、网络、运行行为、
状态卷和验收细节。快速启动请先阅读[项目首页](../README.md)。

## 支持范围

- OpenD：`10.10.7008`。
- 平台：Linux/amd64。
- 部署：单实例 Docker Compose。
- 默认网络：普通 bridge，API 只发布到宿主机 `127.0.0.1`。
- 兼容网络：独立的 `docker-compose.host.yaml`，不得与默认文件叠加。
- 非主要目标：ARM、macOS、Kubernetes、多实例和业务功能扩展。

## 构建版本与产物锁定

当前维护的构建路径只有基于 Ubuntu、名为 `runtime` 的 `linux/amd64`
target。CentOS 7 不再是默认或受维护的发布路径。官方 OpenD 包仍标记为
Ubuntu 18.04，因此运行阶段暂时保留固定 digest 的 Ubuntu 18.04 amd64
镜像作为兼容基线，尽管该版本已结束标准支持。迁移到 Ubuntu 22.04 或更新
版本前，必须在 Linux/amd64 上检查二进制依赖并验证无凭据启动行为；构建
成功本身不能证明兼容。

`opend_version.json` 是仓库构建版本信息的来源。当前 OpenD 产物 SHA-256
特意保持为 `null`：尚未找到发布方提供的签名或校验值，并且审查环境无法
下载该产物。首次本地初始化会自动完成官方 HTTPS 下载和 `.env` 写入；执行
初始化命令即表示接受该 TOFU 行为。仓库 CI 和发布仍会失败关闭，直到维护者
把相同的已审查摘要记录进 `opend_version.json`。不要从未经审查的第三方
复制摘要。

一体化初始化命令会自动调用以下底层命令，下载临时副本并打印候选摘要：

```bash
bash script/download_futu_opend.sh --report-tofu \
  10.10.7008 Futu_OpenD_10.10.7008_Ubuntu18.04.tar.gz
```

`lock-artifact.sh` 会显示来源和候选摘要，并以 `0600` 权限原子更新本地
`.env`，不会输出其中其他配置。下载失败或归档检查失败不会修改文件。首次
下载后自行计算摘要属于首次使用信任（TOFU），不是发布方身份认证。后续匹配
只能证明字节与这次信任决定一致。

仓库维护者仍应把相同值写入 `stableArtifact.sha256`，并将
`integrityStatus` 改为 `tofu-reviewed`，才能启用 Layer 2 和发布 CI。

提交完整性锁后可明确构建：

```bash
docker build --platform linux/amd64 --target runtime \
  --build-arg FUTU_OPEND_VER=10.10.7008 \
  --build-arg FUTU_OPEND_SHA256="${FUTU_OPEND_SHA256:?尚未锁定}" \
  --tag futu-opend:ubuntu-10.10.7008 .
```

运行用户固定为 `10001:10001`。应用文件由 root 拥有并放在
`/opt/futu-opend`。现有 `futu-opend-data` 卷名和挂载路径保持不变。如果
旧卷不能由 UID/GID 10001 写入，应停止并制定经过审查、已有备份的元数据
迁移方案；本项目不会自动 chown 或清理生产状态。

验收部署时应分别记录：

- OpenD 版本及锁定的产物 SHA-256；
- 基础镜像版本和 amd64 manifest digest；
- 用于构建的准确 Git commit；
- 发布后得到的最终镜像 registry digest。

长期部署应查询并固定最终镜像 digest：

```bash
docker pull ghcr.io/OWNER/futu-opend-docker:ubuntu-10.10.7008
docker image inspect --format '{{index .RepoDigests 0}}' \
  ghcr.io/OWNER/futu-opend-docker:ubuntu-10.10.7008
# 使用命令实际返回的 ghcr.io/...@sha256:<digest>。
```

无人值守升级不要使用 `stable` 或 `latest`。本项目不会自动安装 binfmt、
启动 privileged 容器或声称支持原生 arm64。

## 登录模型

`FUTU_LOGIN_MODE` 是本项目的包装层开关，不是 OpenD 原生环境变量：

- `interactive`：用户在私有 TTY 中完成首次登录或重新认证；
- `remember`：日常启动，传递官方的 `-login_account`、可选
  `-area_code` 和 `-login_by_remember=1`。

OpenD 10.10.7008 已从 XML 中移除账号和密码配置。旧变量
`FUTU_ACCOUNT_PWD`、`FUTU_ACCOUNT_PWD_MD5` 会被拒绝，包装脚本不会自动
输入密码或验证码。

官方参考：

- [命令行 OpenD](https://openapi.futunn.com/futu-api-doc/opend/opend-cmd.html)
- [OpenD 10.10.7008 更新日志](https://openapi.futunn.com/futu-api-doc/changelog/changelog.html)
- [加密通信](https://openapi.futunn.com/futu-api-doc/ftapi/protocol.html)
- [SDK 加密配置](https://openapi.futunn.com/futu-api-doc/ftapi/init.html)

## RSA 密钥

一体化初始化命令会在默认 `./futu.pem` 不存在时，以 `umask 077` 和
`0600` 权限生成新密钥；已有文件或符号链接不会被覆盖。也可以自行生成：

```bash
openssl genrsa -traditional -out futu.pem 1024
chmod 0600 futu.pem
```

不要覆盖现有密钥：SDK 客户端必须与 OpenD 使用同一把私钥。一次性的
`futu-key-init` 服务只读挂载宿主机密钥，检查其文件类型、可读性、`0600`
权限和 PKCS#1 PEM 外形，再复制到 `futu-opend-key` 卷，由镜像内实际
`futu` UID/GID 拥有并设为 `0400`。主 OpenD 服务以 `futu` 用户运行，
只读挂载密钥卷。密钥初始化使用 `restart: "no"` 且没有网络命名空间。

`FUTU_OPEND_RSA_FILE_PATH` 必须是 `/.futu` 的直接子项，默认值为
`/.futu/futu.pem`。如使用其他宿主机路径，应在 `.env` 中记录，并在初始化
时传入相同值：

```bash
LOCAL_RSA_FILE_PATH=/absolute/private/path/futu.pem \
  bash script/initialize-and-start.sh
```

## 一体化初始化过程

在私有终端执行：

```bash
bash script/initialize-and-start.sh
```

脚本依次执行：

1. 如果 `.env` 中缺少合法 SHA-256，从固定官方 HTTPS 地址临时下载并检查
   归档，然后自动原子写入 `.env`；不要求项目自定义确认词。
2. 验证最终 Compose 配置；验证失败时不会生成密钥或停止服务。
3. 安全生成缺失的默认 RSA 密钥。
4. 停止日常服务但保留密钥卷和 `futu-opend-data` 状态卷。
5. 以相同 `futu` 用户、`/home/futu` HOME 和状态卷启动交互 OpenD，并发布
   Compose 服务端口。
6. 用户亲自完成密码、验证码及“记住密码”选择。
7. 登录成功后，当前前台 OpenD 进程立即作为 API 服务使用。

项目不根据退出码、目录或包装层锁文件宣称登录成功，也不会启动第二个 OpenD
容器。首次服务保持前台运行，因此没有日常服务的自动重启策略；该会话结束后，
以后再使用下面的 remembered 后台启动命令。

日常启动和日志：

```bash
docker compose --env-file .env -f docker-compose.yaml up -d
docker compose --env-file .env -f docker-compose.yaml logs -f futu-opend
```

记住密码状态缺失或过期时，重新运行一体化初始化命令。不要删除、重命名或
迁移状态卷，也不要无限认证重试。

## 网络

### 默认 bridge

`docker-compose.yaml` 是完整、独立的默认配置：

- 默认网络不是 `internal`，OpenD 可以出站连接；
- OpenD 默认在容器接口 `0.0.0.0` 监听 API；
- API 只发布到宿主机 `127.0.0.1`；
- Telnet 和 WebSocket 默认不写入运行时 XML。

同一 Compose 网络内的容器可以连接
`futu-opend:<FUTU_OPEND_PORT>`，必须将它们视为可信客户端。可在私有终端
审查最终配置，但输出可能包含账号标识：

```bash
docker compose --env-file .env -f docker-compose.yaml config
```

### host 兼容模式

`docker-compose.host.yaml` 是另一个完整配置，不是 override，不得与默认文件
叠加。它使用 `network_mode: host`，没有 `ports`，API 默认绑定
`FUTU_OPEND_HOST_IP=127.0.0.1`。请保持相同项目目录和项目名，以复用现有卷：

```bash
docker compose --env-file .env -f docker-compose.host.yaml config
FUTU_COMPOSE_FILE="$PWD/docker-compose.host.yaml" \
  bash script/initialize-and-start.sh
```

host 只作为兼容回退。本项目尚未实际验证 bridge 或 host 模式的真实认证。

### 可选监听器

未设置或设置为空都表示关闭：

```dotenv
FUTU_OPEND_TELNET_PORT=
FUTU_OPEND_WEBSOCKET_PORT=
```

Telnet 有独立监听地址。如需让同网络可信容器访问，可明确设置；host 模式应
保持在 `127.0.0.1`。WebSocket 默认关闭且不发布到宿主机。非本地 WebSocket
需要官方要求的 SSL 配置，本项目本阶段未实现。RSA 协议加密只适用于 OpenAPI，
不能据此声称 Telnet 或 WebSocket 流量已加密。

## 存活、就绪、停止和日志

Compose 健康检查核对 PID 1 的 `/proc` 进程名，并确认生成的 XML 包含当前
API 端口。它只能证明进程和配置一致，不能证明登录成功、会话有效、API 业务
就绪、加密协商成功或 SDK 往返正常。Docker 不会仅因容器 `unhealthy` 就
重启；重启策略在 PID 1 非零退出时生效。

服务在强制终止前给 `SIGTERM` 最多 30 秒。包装脚本使用 `exec`，因此 OpenD
作为 PID 1 直接接收信号。OpenD 自身 monitor/daemon 和状态落盘行为仍需在
Linux/amd64 上实际验证。

`json-file` 日志限制为三个 10 MiB 文件。本阶段未启用 privileged、修改
宿主机防火墙或 Docker daemon。业务就绪必须通过 SDK 实际返回值确认。

## SDK 连接示例

OpenD 和客户端必须使用同一把私钥，并在创建 context 前启用加密。

宿主机 SDK：

```python
from futu import OpenQuoteContext, SysConfig

SysConfig.enable_proto_encrypt(True)
SysConfig.set_init_rsa_file("/absolute/path/to/futu.pem")
quote_ctx = OpenQuoteContext(host="127.0.0.1", port=11111)
quote_ctx.close()
```

同一 Compose 网络中的可信容器：

```python
from futu import OpenQuoteContext, SysConfig

SysConfig.enable_proto_encrypt(True)
SysConfig.set_init_rsa_file("/run/secrets/futu.pem")
quote_ctx = OpenQuoteContext(host="futu-opend", port=11111)
quote_ctx.close()
```

应将同一密钥只读挂载给客户端，并确保其实际 UID 可读，不要把宿主机权限放宽
到超过 `0600`，也不要把密钥复制进镜像。修改 `FUTU_OPEND_PORT` 时必须同步
修改客户端端口。以上示例仅为文档，未在真实账号上执行。

## 状态卷元数据

项目不会检查或修改现有会话内容。用户可在服务停止时只检查元数据：

```bash
docker compose --env-file .env -f docker-compose.yaml down
docker compose --env-file .env -f docker-compose.yaml run --rm --no-deps \
  --user root --entrypoint stat futu-opend \
  -c '%u:%g %a %F' /home/futu/.com.futunn.FutuOpenD
```

如果所有权与镜像内 `futu` 用户不符，应先准备经过审查、已有备份的迁移方案。
不要自动递归 chown 或清空生产卷。

## 测试与验收

```bash
# 第一层：无需 Docker daemon、凭据或联网 OpenD
npm ci
npm run test:layer1

# 第二层：隔离的无凭据镜像/容器 smoke test
npm run test:smoke

# 第三层默认显示 SKIPPED，公共 CI 永不启用
npm run test:live

# Node 依赖不可用时运行第一层 Shell/配置子集
npm run test:offline
```

第一层仅使用假值和临时资源。第二层不能证明登录或业务就绪。第三层是唯一的
SDK/登录状态验收，必须由用户在私有初始化后显式设置
`RUN_LIVE_TESTS=1`；agent 和公共 CI 均不运行。完整前提、证明边界、超时和
清理范围见[分层测试文档](E2E.md)。

## 免责声明

本项目与[富途证券国际（香港）有限公司](https://www.futuhk.com/)没有隶属
关系。原始许可证和上游归属信息保留在根目录 `LICENSE` 中。
