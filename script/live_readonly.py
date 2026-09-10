#!/usr/bin/env python3
"""Operator-only encrypted GetGlobalState acceptance check."""

import contextlib
import io
import os
import signal
import sys


class LiveTimeout(Exception):
    pass


def fail(message):
    print(f"FAILED: {message}", file=sys.stderr)
    return 1


def positive_int(name, default, maximum):
    raw = os.environ.get(name, str(default))
    try:
        value = int(raw)
    except ValueError:
        raise ValueError(f"{name} must be an integer") from None
    if value < 1 or value > maximum:
        raise ValueError(f"{name} must be between 1 and {maximum}")
    return value


def timed_call(seconds, phase, callback):
    def handle_timeout(_signum, _frame):
        raise LiveTimeout(phase)

    previous = signal.signal(signal.SIGALRM, handle_timeout)
    signal.alarm(seconds)
    try:
        return callback()
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, previous)


def quiet_call(callback):
    # Do not relay SDK connection diagnostics into shared terminal/CI logs.
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return callback()


def main():
    enabled = os.environ.get("RUN_LIVE_TESTS", "0")
    if enabled in ("", "0"):
        print("SKIPPED: live read-only acceptance requires RUN_LIVE_TESTS=1")
        return 0
    if enabled != "1":
        return fail("RUN_LIVE_TESTS must be 0 or 1")

    key_path = os.environ.get("FUTU_OPEND_RSA_FILE_PATH", "")
    if not key_path or not os.path.isabs(key_path):
        return fail("FUTU_OPEND_RSA_FILE_PATH must be an absolute private-key path")
    if not os.path.isfile(key_path) or not os.access(key_path, os.R_OK):
        return fail("FUTU_OPEND_RSA_FILE_PATH is missing, not a file, or unreadable")
    if os.stat(key_path).st_mode & 0o077:
        return fail("FUTU_OPEND_RSA_FILE_PATH must not grant group or other access")

    host = os.environ.get("FUTU_OPEND_HOST", "127.0.0.1")
    if not host or len(host) > 253 or any(c in host for c in "\r\n\0"):
        return fail("FUTU_OPEND_HOST is invalid")

    try:
        port = positive_int("FUTU_OPEND_PORT", 11111, 65535)
        connect_timeout = positive_int("FUTU_LIVE_CONNECT_TIMEOUT", 10, 300)
        request_timeout = positive_int("FUTU_LIVE_REQUEST_TIMEOUT", 10, 300)
    except ValueError as error:
        return fail(str(error))

    require_trd = os.environ.get("FUTU_LIVE_REQUIRE_TRD_LOGIN", "0")
    if require_trd not in ("0", "1"):
        return fail("FUTU_LIVE_REQUIRE_TRD_LOGIN must be 0 or 1")

    try:
        from futu import OpenQuoteContext, RET_OK, SysConfig
    except ImportError:
        return fail("the official futu Python SDK is not installed")

    quote_ctx = None
    try:
        # Encryption is mandatory for this acceptance path and is configured
        # before the context is created, as required by the official SDK docs.
        quiet_call(lambda: SysConfig.enable_proto_encrypt(True))
        quiet_call(lambda: SysConfig.set_init_rsa_file(key_path))
        quote_ctx = timed_call(
            connect_timeout,
            "connection",
            lambda: quiet_call(lambda: OpenQuoteContext(host=host, port=port)),
        )
        ret, data = timed_call(
            request_timeout,
            "request",
            lambda: quiet_call(quote_ctx.get_global_state),
        )
        if ret != RET_OK or not isinstance(data, dict):
            return fail("get_global_state() did not return RET_OK with a state dictionary")

        qot_logined = data.get("qot_logined")
        trd_logined = data.get("trd_logined")
        if qot_logined is not True:
            return fail("get_global_state() reports qot_logined=false")
        if require_trd == "1" and trd_logined is not True:
            return fail("trading-login acceptance was requested but trd_logined=false")

        print(
            "PASSED: live read-only GetGlobalState "
            f"qot_logined=true trd_logined={'true' if trd_logined is True else 'false'}"
        )
        return 0
    except LiveTimeout as error:
        return fail(f"live {error} timed out")
    except Exception:
        # SDK/server exception text may contain endpoint or account details.
        return fail("live SDK connection or request failed; details suppressed")
    finally:
        if quote_ctx is not None:
            try:
                quiet_call(quote_ctx.close)
            except Exception:
                raise SystemExit(fail("SDK quote context could not be closed cleanly"))


if __name__ == "__main__":
    raise SystemExit(main())
