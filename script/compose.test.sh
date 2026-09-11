#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/futu-compose-test.XXXXXX")
PROJECT_NAME=futu-compose-test

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

BASE_ENV=$TEST_ROOT/base.env
EMPTY_ENV=$TEST_ROOT/empty.env
CUSTOM_ENV=$TEST_ROOT/custom.env
FAKE_KEY=$TEST_ROOT/fake.pem
BRIDGE_JSON=$TEST_ROOT/bridge.json
HOST_JSON=$TEST_ROOT/host.json
EMPTY_JSON=$TEST_ROOT/empty.json
CUSTOM_JSON=$TEST_ROOT/custom.json
UNLOCKED_ENV=$TEST_ROOT/unlocked.env

printf '%s\n' 'fake compose test key, not an RSA credential' >"$FAKE_KEY"
chmod 0600 "$FAKE_KEY"

cat >"$BASE_ENV" <<EOF
FUTU_LOGIN_MODE=remember
FUTU_ACCOUNT_ID=fake-compose-account
FUTU_LOGIN_PASSWORD=FAKE_COMPOSE_PASSWORD_MUST_NOT_LEAK
FUTU_OPEND_IP=0.0.0.0
FUTU_OPEND_HOST_IP=127.0.0.1
FUTU_OPEND_RSA_FILE_PATH=/.futu/futu.pem
LOCAL_RSA_FILE_PATH=$FAKE_KEY
FUTU_OPEND_VER=10.10.7008
FUTU_OPEND_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF

cp "$BASE_ENV" "$EMPTY_ENV"
cat >>"$EMPTY_ENV" <<'EOF'
FUTU_OPEND_TELNET_PORT=
FUTU_OPEND_WEBSOCKET_PORT=
EOF

cp "$BASE_ENV" "$CUSTOM_ENV"
printf '%s\n' 'FUTU_OPEND_PORT=12345' >>"$CUSTOM_ENV"
grep -v '^FUTU_OPEND_SHA256=' "$BASE_ENV" >"$UNLOCKED_ENV"

if COMPOSE_DISABLE_ENV_FILE=1 docker compose \
  --project-name "$PROJECT_NAME" \
  --env-file "$UNLOCKED_ENV" \
  -f "$ROOT_DIR/docker-compose.yaml" \
  config >/dev/null 2>&1; then
  printf '%s\n' 'not ok 1 - an unlocked artifact digest must stop Compose rendering' >&2
  exit 1
fi

render() {
  local compose_file=$1
  local env_file=$2
  local output_file=$3
  COMPOSE_DISABLE_ENV_FILE=1 docker compose \
    --project-name "$PROJECT_NAME" \
    --env-file "$env_file" \
    -f "$compose_file" \
    config --format json >"$output_file"
}

render "$ROOT_DIR/docker-compose.yaml" "$BASE_ENV" "$BRIDGE_JSON"
render "$ROOT_DIR/docker-compose.host.yaml" "$BASE_ENV" "$HOST_JSON"
render "$ROOT_DIR/docker-compose.yaml" "$EMPTY_ENV" "$EMPTY_JSON"
render "$ROOT_DIR/docker-compose.yaml" "$CUSTOM_ENV" "$CUSTOM_JSON"

python3 - "$BRIDGE_JSON" "$HOST_JSON" "$EMPTY_JSON" "$CUSTOM_JSON" \
  "$ROOT_DIR/docker-compose.yaml" <<'PY'
import json
import sys

bridge, host, empty, custom = [json.load(open(path, encoding='utf-8')) for path in sys.argv[1:5]]
compose_source = open(sys.argv[5], encoding='utf-8').read()
password_canary = 'FAKE_COMPOSE_PASSWORD_MUST_NOT_LEAK'

for model in (bridge, host, empty, custom):
    rendered = json.dumps(model, sort_keys=True)
    assert password_canary not in rendered
    for candidate in model['services'].values():
        raw_env = candidate.get('environment', {})
        if isinstance(raw_env, dict):
            assert 'FUTU_LOGIN_PASSWORD' not in raw_env
        else:
            assert not any(item.startswith('FUTU_LOGIN_PASSWORD=') for item in raw_env)


def service(model, name='futu-opend'):
    return model['services'][name]


def env_map(model, name='futu-opend'):
    raw = service(model, name)['environment']
    if isinstance(raw, dict):
        return raw
    return dict(item.split('=', 1) for item in raw)


bridge_service = service(bridge)
bridge_env = env_map(bridge)
assert bridge_service.get('network_mode') not in ('host', 'none')
assert not bridge['networks']['default'].get('internal', False)
ports = bridge_service['ports']
assert len(ports) == 1
assert str(ports[0]['target']) == '11111'
assert str(ports[0]['published']) == '11111'
assert ports[0]['host_ip'] == '127.0.0.1'
assert bridge_env['FUTU_OPEND_IP'] == '0.0.0.0'
assert bridge_env['FUTU_OPEND_TELNET_PORT'] == ''
assert bridge_env['FUTU_OPEND_WEBSOCKET_PORT'] == ''
assert bridge_service['user'] == 'futu'
assert bridge_service['platform'] == 'linux/amd64'
assert bridge_service['build']['target'] == 'runtime'
assert bridge_service['restart'] == 'on-failure:3'
assert bridge_service['stop_grace_period'] == '30s'

host_service = service(host)
host_env = env_map(host)
assert host_service['network_mode'] == 'host'
assert host_service['platform'] == 'linux/amd64'
assert not host_service.get('ports')
assert host_env['FUTU_OPEND_IP'] == '127.0.0.1'
assert host_env['FUTU_OPEND_TELNET_PORT'] == ''
assert host_env['FUTU_OPEND_WEBSOCKET_PORT'] == ''

assert bridge['volumes']['futu-opend-data']['name'] == host['volumes']['futu-opend-data']['name']
assert bridge['volumes']['futu-opend-key']['name'] == host['volumes']['futu-opend-key']['name']

key_init = service(bridge, 'futu-key-init')
assert key_init['network_mode'] == 'none'
assert key_init['restart'] == 'no'
assert key_init['user'] == 'root'
assert key_init['platform'] == 'linux/amd64'
assert key_init['build']['target'] == 'runtime'
assert key_init['build']['args']['FUTU_OPEND_SHA256'] == 'a' * 64
source_mount = next(m for m in key_init['volumes'] if m['target'] == '/source/futu.pem')
assert source_mount['type'] == 'bind'
assert source_mount['read_only'] is True
assert 'create_host_path: false' in compose_source
assert 'selinux: Z' in compose_source
# Older Compose v2 releases omit false/default bind options from JSON output.
rendered_bind = source_mount.get('bind', {})
assert rendered_bind.get('create_host_path') in (None, False)
assert rendered_bind.get('selinux') in (None, 'Z')
runtime_key = next(m for m in bridge_service['volumes'] if m['target'] == '/.futu')
assert runtime_key['read_only'] is True

assert env_map(empty)['FUTU_OPEND_TELNET_PORT'] == bridge_env['FUTU_OPEND_TELNET_PORT'] == ''
assert env_map(empty)['FUTU_OPEND_WEBSOCKET_PORT'] == bridge_env['FUTU_OPEND_WEBSOCKET_PORT'] == ''

custom_service = service(custom)
custom_env = env_map(custom)
assert custom_env['FUTU_OPEND_PORT'] == '12345'
assert str(custom_service['ports'][0]['target']) == '12345'
assert str(custom_service['ports'][0]['published']) == '12345'
assert custom_service['ports'][0]['host_ip'] == '127.0.0.1'
health_command = custom_service['healthcheck']['test'][1]
assert '${FUTU_OPEND_PORT}' in health_command
assert '${FUTU_OPEND_RUNTIME_CONFIG:-/tmp/FutuOpenD.xml}' in health_command

print('ok 1 - missing artifact digest fails closed before Compose can build')
print('ok 2 - bridge publishes only API on host loopback and stays externally connected')
print('ok 3 - standalone host mode has no ports and binds API to loopback')
print('ok 4 - both complete files resolve the same state and key volume names')
print('ok 5 - key preparation is isolated and the runtime key mount is read-only')
print('ok 6 - unset and empty optional listener ports both remain disabled')
print('ok 7 - custom API port aligns runtime config, health validation, and loopback client endpoint')
print('ok 8 - wrapper-only login password is absent from rendered container configuration')
print('1..8')
PY
