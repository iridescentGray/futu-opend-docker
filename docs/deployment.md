# 部署与运维详解

本文保存 FutuOpenD Docker / Podman 项目的构建锁定、登录、密钥、网络、运行行为、
状态卷和验收细节。快速启动请先阅读[项目首页](../README.md)。

## 支持范围

- OpenD：`10.10.7008`。
- 容器平台：Linux/amd64。
- 宿主平台：Linux/amd64；macOS Apple Silicon 通过 Docker Desktop x86 仿真。
- 部署：单实例 Docker Compose 或原生 rootless Podman；Linux/amd64 的发行包
  不依赖 Podman Compose。macOS Apple Silicon 发行包仍使用 Docker Desktop。
- 默认网络：普通 bridge，API 只发布到宿主机 `127.0.0.1`。
- 可选集成网络：由部署环境预创建的 external network，通过
  `FUTU_SHARED_NETWORK` 加入，不归本 Compose project 所有。
- 兼容网络：独立的 `docker-compose.host.yaml`，不得与默认文件叠加。
- 非主要目标：原生 Linux/arm64、原生 macOS OpenD、Kubernetes、多实例和业务
  功能扩展。

## 面向使用者的发行包

当前发行版 `v10.10.7008-r6` 包含 Docker Compose/原生 Podman 双引擎支持、
可选的可信容器网络，以及发行包启动器的 `-h` / `--help`。Linux/amd64 的
Podman 路径不依赖外部 Compose provider。

正式使用路径是版本化、无源码的宿主平台发行包。当前同时生成
`linux-amd64` 和 `macos-apple-silicon` 两个归档；两者都运行同一个经过测试、
按 digest 固定的 Linux/amd64 容器镜像。macOS 包是 Apple Silicon 宿主兼容包，
不是原生 arm64 OpenD 镜像。包内只有
`compose.yaml`、`env.example`、`futu-opend` 管理命令、受限登录代理和简短
说明；不包含 Dockerfile、构建上下文或测试。两个 Compose 服务使用同一个
GHCR 镜像，并固定到发布后得到的 registry SHA-256 digest，因此用户机器不
下载 OpenD 安装包，也不执行本地镜像构建。

发行包命令：

```bash
cp env.example .env
chmod 0600 .env
# 编辑 .env
./futu-opend init     # 首次登录或重新认证；前台服务
./futu-opend start    # 后续 remembered 后台启动
./futu-opend status
./futu-opend logs
./futu-opend stop     # 保留密钥卷和登录状态卷
```

`init` 和 `start` 代表 OpenD 的两种官方登录生命周期，不应在首次登录时连续
执行。`init` 登录成功后的同一个前台进程已经是 API 服务；只有该会话结束或
主机重启后，才使用 `start` 从命名卷中的 remembered 状态后台启动。

Linux 启动器默认使用 `FUTU_CONTAINER_ENGINE=auto`，先实际检查
`docker compose version`，不可用时再检查原生 `podman`。Docker 命令存在但
Compose 子命令不可用时也会选择 Podman。显式模式不会回退：

```bash
FUTU_CONTAINER_ENGINE=docker ./futu-opend start
FUTU_CONTAINER_ENGINE=podman ./futu-opend start
```

不支持其他值，也不需要 `alias docker=podman`。发行包的 Podman 路径直接使用
`podman volume`、`podman run`、`podman stop` 和 `podman logs`，不安装或调用
外部 Compose provider。源码开发路径仍保留 Podman Compose 模型验证。

推送符合 `v<OpenD版本>-r<发行修订>` 的标签（例如
`v10.10.7008-r1`）会触发发行工作流。工作流依次运行 Layer 1、对待发布镜像
运行 Layer 2、推送不可变修订标签、解析 registry digest、生成两种宿主发行包
及其 SHA-256 文件，最后创建同名 GitHub Release。实际发布仍要求
`opend_version.json` 中存在已审查的 OpenD 产物锁。

macOS Apple Silicon 包的启动器在接触 Docker 前核对 `Darwin/arm64`，并检查
Compose v2、可访问的 Docker engine 及 Linux container 模式。建议 Docker
Desktop 使用 Apple Virtualization framework 并启用 Rosetta。Docker VMM 不
支持 Rosetta 时仍可能通过较慢的仿真运行，但不作为性能保证。macOS 自带
LibreSSL 不接受 OpenSSL 3 的 `-traditional` 参数，因此启动器会在该参数失败
时使用 LibreSSL 默认输出，并继续要求最终密钥为未加密 PKCS#1 格式。

## 构建版本与产物锁定

当前维护的构建路径只有基于 Ubuntu、名为 `runtime` 的 `linux/amd64`
target。CentOS 7 不再是默认或受维护的发布路径。官方 OpenD 包仍标记为
Ubuntu 18.04，因此运行阶段暂时保留固定 digest 的 Ubuntu 18.04 amd64
镜像作为兼容基线，尽管该版本已结束标准支持。迁移到 Ubuntu 22.04 或更新
版本前，必须在 Linux/amd64 上检查二进制依赖并验证无凭据启动行为；构建
成功本身不能证明兼容。

`opend_version.json` 是仓库构建版本信息的来源。当前 OpenD 产物通过固定
富途官方 HTTPS 地址的临时下载、归档结构检查和本地 SHA-256 计算完成 TOFU
锁定。该摘要只能证明后续下载字节一致，不是发布方提供的签名或独立来源认证。
版本升级会主动清空旧锁，维护者必须重新审查新产物；不要从未经审查的第三方
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

已审查值同时记录在 `stableArtifact.sha256` 和 `.env.example`，且
`integrityStatus` 为 `tofu-reviewed`，因此 Layer 2 和受信任发布 CI 可以
执行。首次本地初始化仍会对用户自己的下载进行同样的一致性检查。

提交完整性锁后可明确构建：

```bash
docker build --platform linux/amd64 --target runtime \
  --build-arg FUTU_OPEND_VER=10.10.7008 \
  --build-arg FUTU_OPEND_SHA256="${FUTU_OPEND_SHA256:?尚未锁定}" \
  --tag futu-opend:ubuntu-10.10.7008 .
```

Podman 使用同一份 `Dockerfile`，不维护重复的 `Containerfile`：

```bash
podman build --platform linux/amd64 --target runtime \
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
`FUTU_ACCOUNT_PWD`、`FUTU_ACCOUNT_PWD_MD5` 会被拒绝。本项目另行定义了仅
供宿主机登录包装器使用的 `FUTU_LOGIN_PASSWORD`：非空时 Expect 代理在官方
密码提示后提交一次，空值或未设置时由用户在终端输入。该变量不是 OpenD 原生
配置，不写入 XML、不进入 OpenD 参数或容器环境。代理同时预填账号、自动选择
记住密码 `Y`，并在官方手机验证码命令提示后转换用户输入的裸 6 位数字；它
不启用 Telnet，也不写会话 transcript。

密码可以写入本地、已忽略的 `.env`：

```dotenv
FUTU_LOGIN_PASSWORD='仅保存在本机的密码'
```

外层成对的单引号或双引号会被移除，内部字符原样提交；不允许换行。也可只在
当前 shell 导出同名变量，shell 环境优先于 `.env`。将密码放入环境变量或
`.env` 会扩大本地暴露面：同 UID 进程检查、错误的备份/同步设置或文件权限
都可能泄露密码。`.env` 必须保持未跟踪；初始化脚本会在读取登录配置前将其
权限限制为 `0600`。不要在共享终端运行或启用 shell xtrace。包装器会关闭
自身 xtrace，不会打印密码，并在启动 Expect 前从自身环境删除该变量。

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

rootless Podman 使用 user namespace 将容器 UID/GID 映射到 subordinate ID；
初始化器仍在容器内验证密钥为 `10001:10001`、模式 `0400`。不要使用
`sudo podman`、`--userns=keep-id` 或会递归修改宿主文件的 `:U`。宿主私钥
bind mount 保持只读、禁止自动创建，并使用私有 SELinux `Z` relabel，以支持
Fedora、RHEL、Rocky、AlmaLinux 等 enforcing 主机；relabel 仅作用于该私钥。

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

源码流程同样自动选择引擎，也可明确选择：

```bash
FUTU_CONTAINER_ENGINE=docker bash script/initialize-and-start.sh
FUTU_CONTAINER_ENGINE=podman bash script/initialize-and-start.sh
```

脚本依次执行：

1. 如果 `.env` 中缺少合法 SHA-256，从固定官方 HTTPS 地址临时下载并检查
   归档，然后自动原子写入 `.env`；不要求项目自定义确认词。
2. 验证最终 Compose 配置；验证失败时不会生成密钥或停止服务。
3. 安全生成缺失的默认 RSA 密钥。
4. 停止日常服务但保留密钥卷和 `futu-opend-data` 状态卷。
5. 以相同 `futu` 用户、`/home/futu` HOME 和状态卷启动交互 OpenD，并发布
   Compose 服务端口。
6. Expect 代理从 shell 环境或 `.env` 预填账号；非空
   `FUTU_LOGIN_PASSWORD` 会在官方密码提示后自动提交一次，未设置时用户亲自
   输入密码。代理自动选择记住密码 `Y`。出现官方手机验证码命令提示时，用户
   只输入 6 位数字，由代理转换为完整命令。
7. 登录成功后，当前前台 OpenD 进程立即作为 API 服务使用。

项目不根据退出码、目录或包装层锁文件宣称登录成功，也不会启动第二个 OpenD
容器。首次服务保持前台运行，因此没有日常服务的自动重启策略；该会话结束后，
以后再使用下面的 remembered 后台启动命令。

Expect 是宿主机依赖，不会安装进运行镜像。登录期间外层脚本关闭本地键盘
回显并在退出时恢复。包装器通过 Expect 专用环境变量短暂传递密码，Expect
读取后立即删除该变量，再启动 Docker/OpenD；密码不进入 Docker/OpenD 的
argv、环境变量或 XML。错误密码只自动提交一次，再次出现密码提示时以状态
`77` 停止，不会无限重试。但 OpenD 可能回显展开后的验证码运维命令，因此
认证期间不得录制终端或上传原始输出。图形验证码及未知的新提示不会被自动
处理。

日常启动和日志：

```bash
docker compose --env-file .env -f docker-compose.yaml up -d
docker compose --env-file .env -f docker-compose.yaml logs -f futu-opend
```

Podman 下使用相同文件，但日常源码启动应显式执行安全顺序：

```bash
podman compose --env-file .env -f docker-compose.yaml \
  run --rm --no-deps futu-key-init
podman compose --env-file .env -f docker-compose.yaml \
  up -d --no-deps futu-opend
```

需要 external integration network 时，源码初始化器在非空
`FUTU_SHARED_NETWORK` 下自动叠加 `docker-compose.integration.yaml`。日常源码
启动的等价安全顺序为：

```bash
podman network exists trading-backend || podman network create trading-backend
FUTU_CONTAINER_ENGINE=podman FUTU_SHARED_NETWORK=trading-backend \
  bash script/initialize-and-start.sh

FUTU_SHARED_NETWORK=trading-backend podman compose --env-file .env \
  -f docker-compose.yaml -f docker-compose.integration.yaml \
  run --rm --no-deps futu-key-init
FUTU_SHARED_NETWORK=trading-backend podman compose --env-file .env \
  -f docker-compose.yaml -f docker-compose.integration.yaml \
  up -d --no-deps futu-opend
```

初始化脚本与发行包启动器已经自动执行该顺序，不依赖 provider 对
`depends_on.condition` 的实现。Compose 中仍保留
`service_completed_successfully`，保护现有直接 Docker Compose 工作流。

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

### 可信容器 external network

`docker-compose.integration.yaml` 是唯一允许叠加到默认 bridge 文件的可选
override。它只把 `futu-opend` 同时加入 default network 和部署环境拥有的
external network，不改变端口、密钥、登录、状态卷或 key initializer。它不能
与 `docker-compose.host.yaml` 组合。

部署环境先创建网络；两个项目必须由同一个普通 Unix 用户、同一个 rootless
Podman storage 运行：

```bash
podman network exists trading-backend || podman network create trading-backend
FUTU_CONTAINER_ENGINE=podman FUTU_SHARED_NETWORK=trading-backend \
  ./futu-opend init
FUTU_CONTAINER_ENGINE=podman FUTU_SHARED_NETWORK=trading-backend \
  ./futu-opend start
```

若 Docker 与 Podman 同时存在，服务器不能依赖默认 `auto`，因为它会优先选择
Docker Compose。不要使用 `sudo podman` 或 `alias docker=podman`。

连接契约：

| Client                      | Address            | Trust boundary         |
| --------------------------- | ------------------ | ---------------------- |
| 宿主机 SDK                  | `127.0.0.1:11111`  | 宿主机本地运维         |
| external network 内可信容器 | `futu-opend:11111` | `trading-backend` 成员 |

不要使用固定容器 IP、公网 IP 回绕、host network 或
`0.0.0.0:11111` host publish。`./futu-opend stop` / Compose `down` 会删除项目
自己的 default network，但 external network 继续存在；它只能由部署环境显式
管理。任何加入该网络的容器都能接触 OpenAPI，应视为可信客户端。

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

Podman 将 `json-file` 作为 `k8s-file` 的兼容名称并支持 `max-size`。Docker 的
源码 Compose 验证中的 `max-file` 选项在不同 Podman Compose provider 上可能
有版本差异。发行包的原生 Podman 路径改用 `k8s-file` 和 `max-size`，不再经过
provider；Docker 路径继续保留 `json-file` 的 `max-size`/`max-file` 轮转。

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

# Linux/amd64 rootless Podman：构建、Compose 与密钥卷 smoke test
npm run test:podman-smoke

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
关系，也未获得其赞助、背书或认可。本项目不提供投资建议；使用者应自行遵守
适用协议、法律法规和账户权限要求，并承担使用风险。面向人工及自动化审查的
完整中英双语声明见根目录 [`DISCLAIMER.md`](../DISCLAIMER.md)。原始许可证和
上游归属信息保留在根目录 `LICENSE` 中。
