# Futu 新闻读取 demo

这个示例通过宿主机的 `127.0.0.1:11111` 连接已运行的 Futu OpenD，使用
`get_search_news()` 按关键词读取新闻。它只创建行情连接，不创建交易连接，也
不会下单。

依赖使用 `uv` 管理，并精确锁定为与本仓库 OpenD 相同的
`futu-api==10.10.7008`。连接默认启用协议加密，因此客户端必须使用与 OpenD
相同的 RSA 私钥。

## 安装

在仓库根目录执行：

```bash
uv sync --project examples/futu-news-demo --locked
```

## 运行

默认读取普通新闻：

```bash
uv run --project examples/futu-news-demo \
  python examples/futu-news-demo/news_demo.py 腾讯 \
  --rsa-key ./futu.pem
```

读取英伟达相关的最近 20 条全部资讯（包括新闻、公告和评级）：

```bash
uv run --project examples/futu-news-demo \
  python examples/futu-news-demo/news_demo.py NVDA \
  --count 20 \
  --type all \
  --rsa-key ./futu.pem
```

## VS Code 快速启动

安装 VS Code 的 Python 扩展后，打开仓库根目录，进入“运行和调试”，选择
`Futu: 搜索新闻` 并按 `F5`。启动配置会先运行 `uv sync --locked`，再依次询问
关键词、返回条数和资讯类型。

默认连接 `127.0.0.1:11111`，并使用仓库根目录的 `futu.pem`。如果你的私钥或
OpenD 地址不同，请修改 `.vscode/launch.json` 中对应的环境变量。

可选类型为 `all`、`news`、`notice`、`rating`。也可以使用环境变量
`FUTU_OPEND_HOST`、`FUTU_OPEND_PORT` 和 `FUTU_OPEND_RSA_FILE_PATH`，但示例
不会自动读取仓库的 `.env`。

如果私钥不是默认路径，请传入它在宿主机上的路径；不要传容器内的
`/.futu/futu.pem`。私钥必须仅限当前用户访问：

```bash
chmod 600 /absolute/private/path/futu.pem
```

接口返回失败时，先确认 OpenD 已完成行情登录且客户端使用了同一把 RSA 私钥。
容器 `healthy` 只代表进程存活，不代表新闻接口已经就绪或账号具备相关权限。

官方参考：

- [行情接口总览](https://openapi.futunn.com/futu-api-doc/quote/overview.html)
- [SDK 加密配置](https://openapi.futunn.com/futu-api-doc/ftapi/init.html)
