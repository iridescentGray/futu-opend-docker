#!/usr/bin/env python3
"""Search Futu news through a local encrypted OpenD connection."""

from __future__ import annotations

import argparse
import os
import stat
import sys
from pathlib import Path


def positive_int(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("必须是大于 0 的整数")
    return number


def port_number(value: str) -> int:
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("端口必须在 1 到 65535 之间")
    return port


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="通过本机 Futu OpenD 搜索新闻（只读、RSA 加密）"
    )
    parser.add_argument("keyword", help="搜索关键词，例如：腾讯、NVDA、降息")
    parser.add_argument(
        "--count",
        type=positive_int,
        default=10,
        help="最多返回多少条，默认 10",
    )
    parser.add_argument(
        "--type",
        choices=("all", "news", "notice", "rating"),
        default="news",
        help="资讯类型，默认 news",
    )
    parser.add_argument(
        "--host",
        default=os.environ.get("FUTU_OPEND_HOST", "127.0.0.1"),
        help="OpenD 地址，默认 127.0.0.1",
    )
    parser.add_argument(
        "--port",
        type=port_number,
        default=os.environ.get("FUTU_OPEND_PORT", "11111"),
        help="OpenD 端口，默认 11111",
    )
    parser.add_argument(
        "--rsa-key",
        default=os.environ.get("FUTU_OPEND_RSA_FILE_PATH", "./futu.pem"),
        help="与 OpenD 相同的 RSA 私钥路径，默认 ./futu.pem",
    )
    return parser.parse_args()


def validate_key(path_value: str) -> Path:
    key_path = Path(path_value).expanduser().resolve()
    if not key_path.is_file() or not os.access(key_path, os.R_OK):
        raise ValueError("RSA 私钥不存在、不是普通文件或不可读")

    mode = stat.S_IMODE(key_path.stat().st_mode)
    if mode & 0o077:
        raise ValueError("RSA 私钥权限过宽，请先执行 chmod 600 <私钥路径>")
    return key_path


def print_news(data) -> None:
    if data.empty:
        print("没有找到匹配的资讯。")
        return

    for index, row in data.reset_index(drop=True).iterrows():
        securities = row.get("related_securities") or []
        if not isinstance(securities, (list, tuple)):
            securities = [str(securities)]

        print(f"\n[{index + 1}] {row.get('title', '')}")
        print(
            "    "
            f"时间: {row.get('publish_time', '')}  "
            f"来源: {row.get('source', '')}  "
            f"类型: {row.get('news_sub_type', '')}"
        )
        if securities:
            print(f"    关联标的: {', '.join(map(str, securities))}")
        if row.get("url"):
            print(f"    链接: {row['url']}")


def main() -> int:
    args = parse_args()

    try:
        key_path = validate_key(args.rsa_key)
    except (OSError, ValueError) as error:
        print(f"配置错误: {error}", file=sys.stderr)
        return 2

    try:
        from futu import NewsSubType, OpenQuoteContext, RET_OK, SysConfig
    except ImportError:
        print("依赖未安装，请先执行 uv sync --locked", file=sys.stderr)
        return 2

    news_types = {
        "all": NewsSubType.ALL,
        "news": NewsSubType.NEWS,
        "notice": NewsSubType.NOTICE,
        "rating": NewsSubType.RATING,
    }

    quote_ctx = None
    try:
        SysConfig.enable_proto_encrypt(True)
        SysConfig.set_init_rsa_file(str(key_path))
        quote_ctx = OpenQuoteContext(host=args.host, port=args.port)

        ret, data = quote_ctx.get_search_news(
            keyword=args.keyword,
            max_count=args.count,
            news_sub_type=news_types[args.type],
        )
        if ret != RET_OK:
            print(f"读取失败: {data}", file=sys.stderr)
            return 1

        print_news(data)
        return 0
    except Exception as error:
        print(f"连接或请求失败: {error}", file=sys.stderr)
        return 1
    finally:
        if quote_ctx is not None:
            try:
                quote_ctx.close()
            except Exception:
                print("警告: 行情连接未能正常关闭", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
