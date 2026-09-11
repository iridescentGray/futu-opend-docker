#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

readonly SUPPORTED_OPEND_VERSION=10.10.7008

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-64}"
}

validate_text() {
  local name=$1
  local value=$2
  [[ -n $value ]] || die "$name must not be empty"
  [[ $value != *$'\n'* && $value != *$'\r'* ]] ||
    die "$name must not contain line breaks"
}

validate_address() {
  local name=$1
  local value=$2
  validate_text "$name" "$value"
  [[ $value =~ ^[A-Za-z0-9._:-]+$ ]] ||
    die "$name contains unsupported characters"
}

validate_port() {
  local name=$1
  local value=$2
  [[ $value =~ ^[0-9]+$ ]] || die "$name must be an integer from 1 to 65535"
  ((${#value} <= 5)) || die "$name must be an integer from 1 to 65535"
  ((10#$value >= 1 && 10#$value <= 65535)) ||
    die "$name must be an integer from 1 to 65535"
}

validate_absolute_path() {
  local name=$1
  local value=$2
  validate_text "$name" "$value"
  [[ $value == /* ]] || die "$name must be an absolute path"
}

xml_escape() {
  local input=$1
  local output=''
  local char
  local i

  for ((i = 0; i < ${#input}; i++)); do
    char=${input:i:1}
    case "$char" in
    '&') output+='&amp;' ;;
    '<') output+='&lt;' ;;
    '>') output+='&gt;' ;;
    '"') output+='&quot;' ;;
    "'") output+='&apos;' ;;
    *) output+=$char ;;
    esac
  done

  printf '%s' "$output"
}

login_mode=${FUTU_LOGIN_MODE-}
opend_version=${FUTU_OPEND_VERSION-}
account_id=${FUTU_ACCOUNT_ID-}
area_code=${FUTU_ACCOUNT_AREA_CODE-}

opend_bin=${FUTU_OPEND_BIN:-/opt/futu-opend/FutuOpenD}
config_template=${FUTU_OPEND_CONFIG_TEMPLATE:-/etc/futu-opend/FutuOpenD.xml}
runtime_config=${FUTU_OPEND_RUNTIME_CONFIG:-/tmp/FutuOpenD.xml}

opend_ip=${FUTU_OPEND_IP:-127.0.0.1}
opend_port=${FUTU_OPEND_PORT:-11111}
telnet_port=${FUTU_OPEND_TELNET_PORT-}
telnet_ip=${FUTU_OPEND_TELNET_IP:-127.0.0.1}
websocket_port=${FUTU_OPEND_WEBSOCKET_PORT-}
websocket_ip=${FUTU_OPEND_WEBSOCKET_IP:-127.0.0.1}
rsa_path=${FUTU_OPEND_RSA_FILE_PATH-/.futu/futu.pem}
home_dir=${HOME-}

[[ $opend_version == "$SUPPORTED_OPEND_VERSION" ]] ||
  die "this wrapper supports OpenD $SUPPORTED_OPEND_VERSION only; got an unset or different FUTU_OPEND_VERSION"

case "$login_mode" in
interactive | remember) ;;
*) die 'FUTU_LOGIN_MODE must be interactive or remember' ;;
esac

if [[ -n ${FUTU_ACCOUNT_PWD-} || -n ${FUTU_ACCOUNT_PWD_MD5-} ]]; then
  die 'password environment variables are unsupported by OpenD 10.10.7008; remove them and follow the interactive initialization flow in README.md'
fi

validate_absolute_path HOME "$home_dir"
validate_absolute_path FUTU_OPEND_BIN "$opend_bin"
[[ -x $opend_bin ]] || die 'FUTU_OPEND_BIN must point to an executable file'
validate_absolute_path FUTU_OPEND_CONFIG_TEMPLATE "$config_template"
[[ -r $config_template ]] ||
  die 'FUTU_OPEND_CONFIG_TEMPLATE must point to a readable file'
validate_absolute_path FUTU_OPEND_RUNTIME_CONFIG "$runtime_config"

validate_address FUTU_OPEND_IP "$opend_ip"
validate_port FUTU_OPEND_PORT "$opend_port"

if [[ -n $telnet_port ]]; then
  validate_port FUTU_OPEND_TELNET_PORT "$telnet_port"
  validate_address FUTU_OPEND_TELNET_IP "$telnet_ip"
fi

if [[ -n $websocket_port ]]; then
  validate_port FUTU_OPEND_WEBSOCKET_PORT "$websocket_port"
  validate_address FUTU_OPEND_WEBSOCKET_IP "$websocket_ip"
  case "$websocket_ip" in
  127.0.0.1 | ::1 | localhost) ;;
  *) die 'non-loopback WebSocket is unsupported until TLS certificate configuration is implemented' ;;
  esac
fi

if [[ -n $rsa_path ]]; then
  validate_absolute_path FUTU_OPEND_RSA_FILE_PATH "$rsa_path"
  [[ -r $rsa_path ]] || die 'FUTU_OPEND_RSA_FILE_PATH must point to a readable file'
else
  case "$opend_ip" in
  127.0.0.1 | ::1 | localhost) ;;
  *) die 'a readable RSA private key is required when the API bind address is not loopback' ;;
  esac
fi

opend_args=()
case "$login_mode" in
interactive)
  [[ -t 0 && -t 1 ]] ||
    die 'interactive login requires an attached stdin and stdout TTY; use the private-terminal command in README.md'
  ;;
remember)
  validate_text FUTU_ACCOUNT_ID "$account_id"
  if [[ -n $area_code ]]; then
    [[ $area_code =~ ^\+[0-9]{1,4}$ ]] ||
      die 'FUTU_ACCOUNT_AREA_CODE must be a plus sign followed by 1 to 4 digits'
  fi
  opend_args+=("-login_account=$account_id")
  if [[ -n $area_code ]]; then
    opend_args+=("-area_code=$area_code")
  fi
  opend_args+=("-login_by_remember=1")
  ;;
esac

state_dir=$home_dir/.com.futunn.FutuOpenD
mkdir -p "$state_dir" || die 'unable to create the OpenD state directory'
[[ -w $state_dir ]] || die 'the OpenD state directory is not writable'

command -v flock >/dev/null 2>&1 ||
  die 'flock is required to prevent concurrent OpenD processes on the shared state volume'

lock_file=$state_dir/.futu-opend-wrapper.lock
exec 9>"$lock_file"
flock -n 9 ||
  die 'another OpenD process is already using this HOME state directory' 75

template=$(<"$config_template")
api_ip_xml=$(xml_escape "$opend_ip")
api_port_xml=$(xml_escape "$opend_port")

telnet_xml=''
if [[ -n $telnet_port ]]; then
  telnet_ip_xml=$(xml_escape "$telnet_ip")
  telnet_port_xml=$(xml_escape "$telnet_port")
  telnet_xml=$'\t\t<telnet_ip>'"$telnet_ip_xml"$'</telnet_ip>\n\t\t<telnet_port>'"$telnet_port_xml"'</telnet_port>'
fi

rsa_xml=''
if [[ -n $rsa_path ]]; then
  rsa_path_xml=$(xml_escape "$rsa_path")
  rsa_xml=$'\t\t<rsa_private_key>'"$rsa_path_xml"'</rsa_private_key>'
fi

websocket_xml=''
if [[ -n $websocket_port ]]; then
  websocket_ip_xml=$(xml_escape "$websocket_ip")
  websocket_port_xml=$(xml_escape "$websocket_port")
  websocket_xml=$'\t\t<websocket_ip>'"$websocket_ip_xml"$'</websocket_ip>\n\t\t<websocket_port>'"$websocket_port_xml"'</websocket_port>'
fi

runtime_xml=$template
replace_placeholder() {
  local marker=$1
  local replacement=$2
  local prefix
  local suffix

  [[ $runtime_xml == *"$marker"* ]] ||
    die 'the OpenD XML template is missing a required placeholder'
  prefix=${runtime_xml%%"$marker"*}
  suffix=${runtime_xml#*"$marker"}
  runtime_xml=$prefix$replacement$suffix
}

# Do not use Bash pattern replacement here. On Bash 5 with patsub_replacement,
# an ampersand in an XML entity such as &amp; expands back to the matched marker.
replace_placeholder '###FUTU_OPEND_IP###' "$api_ip_xml"
replace_placeholder '###FUTU_OPEND_PORT###' "$api_port_xml"
replace_placeholder '###FUTU_OPEND_TELNET_CONFIG###' "$telnet_xml"
replace_placeholder '###FUTU_OPEND_RSA_CONFIG###' "$rsa_xml"
replace_placeholder '###FUTU_OPEND_WEBSOCKET_CONFIG###' "$websocket_xml"

[[ $runtime_xml != *'###FUTU_OPEND_'* ]] ||
  die 'the OpenD XML template contains an unsupported placeholder'

runtime_dir=${runtime_config%/*}
[[ -n $runtime_dir ]] || runtime_dir=/
[[ -d $runtime_dir && -w $runtime_dir ]] ||
  die 'the FUTU_OPEND_RUNTIME_CONFIG parent directory must exist and be writable'
printf '%s\n' "$runtime_xml" >"$runtime_config"
chmod 0600 "$runtime_config"

opend_args+=("-cfg_file=$runtime_config")
printf 'Starting FutuOpenD in %s login mode.\n' "$login_mode"

# Keep OpenD as PID 1 and preserve its stdin/stdout, signals, and exit status.
# Do not pass no_monitor until the target Linux/amd64 binary behavior is verified.
exec "$opend_bin" "${opend_args[@]}"
