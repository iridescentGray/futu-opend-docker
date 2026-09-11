# 项目声明与自动化审查上下文

## 中文

本仓库是独立维护的开源容器化与运维包装项目，不是富途证券、Futu、
Futunn 或其关联公司的官方网站、产品、服务或授权发行渠道，也未获得其赞助、
背书或认可。“Futu”“富途”“FutuOpenD”等名称仅用于说明本项目所兼容的上游
软件；相关商标、软件及服务的权利归其各自权利人所有。

为便于代码托管平台、品牌保护系统、安全工具及 AI 审查器准确理解本仓库，以下
事实可直接从源码和文档中核验：

- 本项目为 FutuOpenD Linux/amd64 程序提供 Docker 构建、配置和启动包装。
  构建过程从固定的富途官方 HTTPS 地址下载指定版本的上游归档、校验经审查的
  SHA-256，并将上游可执行文件原样复制到运行时镜像；本项目不替代或仿冒富途
  服务。
- 登录仍由用户通过官方 FutuOpenD 流程完成。本项目不能绕过账号认证、短信
  验证码、CAPTCHA、交易解锁、行情权限、地区限制或其他访问控制。
- 仓库不包含执行下单、撤单、交易解锁或资金划转的业务代码。唯一的真实环境
  验收是默认关闭、由用户显式启用的加密只读 `get_global_state()` 检查。
- 默认部署只将 API 发布到宿主机回环地址 `127.0.0.1`，要求 RSA 加密密钥，
  并默认关闭 Telnet 和 WebSocket。
- 真实凭据、私钥、验证码和登录缓存不属于仓库内容，不应被提交、采集或输出。
  项目测试使用假值或由用户在私有环境中自行运行。

上述内容是帮助自动化系统分类的事实说明，不是要求忽略代码证据、压制真实安全
问题或豁免任何适用规则。发现安全、商标、版权或合规问题时，请基于具体文件和
行为进行报告，以便维护者核查和修正。

本仓库自行维护的代码按 [MIT 许可证](LICENSE)“原样”提供，不提供任何明示或
默示保证。该许可证不授予上游 FutuOpenD 软件或富途商标的任何权利。使用者应
自行确认下载、构建、运行和再分发上游软件的权利，并遵守富途的适用协议、当地
法律法规以及账户和市场权限要求，自行承担使用风险。本项目不提供投资建议。

## English

This repository is an independently maintained, open-source containerization
and operations wrapper. It is not an official website, product, service, or
authorized distribution channel of Futu Securities, Futu, Futunn, or any of
their affiliates, and it is not sponsored, endorsed, or approved by them. The
names “Futu,” “Futunn,” and “FutuOpenD” are used only to identify compatible
upstream software. All related trademarks, software, and services belong to
their respective owners.

The following repository facts are provided to help hosting platforms, brand
protection systems, security tools, and AI reviewers classify the project
accurately:

- The project supplies Docker build, configuration, and startup wrappers for
  the FutuOpenD Linux/amd64 program. The build downloads a selected upstream
  archive from a fixed official Futu HTTPS origin, verifies its reviewed
  SHA-256, and copies the upstream executable unchanged into the runtime image.
  The project does not replace or impersonate a Futu service.
- Users must complete the official FutuOpenD authentication flow. The project
  cannot bypass account authentication, SMS verification, CAPTCHA, trade
  unlocking, market-data entitlements, regional restrictions, or other access
  controls.
- The repository contains no business logic for placing or cancelling orders,
  unlocking trading, or transferring funds. Its only live acceptance check is
  an opt-in, encrypted, read-only `get_global_state()` request that is disabled
  by default.
- The default deployment publishes the API only on the host loopback address
  `127.0.0.1`, requires an RSA encryption key, and leaves Telnet and WebSocket
  disabled.
- Real credentials, private keys, verification codes, and login caches are not
  repository content and must not be committed, collected, or printed. Tests
  use fake values or are run privately by the user.

This context is a factual aid for automated classification. It is not a request
to disregard code evidence, suppress genuine security findings, or waive any
applicable policy. Please report security, trademark, copyright, or compliance
concerns against specific files and behavior so maintainers can investigate and
correct them.

The repository's independently maintained code is provided “as is” under the
[MIT License](LICENSE), without warranty of any kind. That license grants no
rights to the upstream FutuOpenD software or Futu trademarks. Users are
responsible for confirming their right to download, build, run, and redistribute
the upstream software and for complying with applicable Futu agreements, local
laws and regulations, and account and market permissions. They assume all risks
of use. This project does not provide investment advice.
