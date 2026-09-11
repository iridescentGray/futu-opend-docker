#!/usr/bin/env bash

# Sourceable container-engine selection shared by source and release workflows.
# The caller is expected to enable its preferred strict-shell options.

container_engine=''
compose_cmd=()

container_compose_available() {
  local candidate=$1
  command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" compose version >/dev/null 2>&1
}

resolve_container_engine() {
  local requested=${FUTU_CONTAINER_ENGINE:-auto}

  case "$requested" in
  auto)
    if container_compose_available docker; then
      container_engine=docker
    elif container_compose_available podman; then
      container_engine=podman
    else
      printf '%s\n' \
        'ERROR: neither Docker Compose nor Podman Compose is available' >&2
      return 69
    fi
    ;;
  docker | podman)
    if ! container_compose_available "$requested"; then
      printf 'ERROR: FUTU_CONTAINER_ENGINE=%s requires %s compose\n' \
        "$requested" "$requested" >&2
      return 69
    fi
    container_engine=$requested
    ;;
  *)
    printf '%s\n' \
      'ERROR: FUTU_CONTAINER_ENGINE must be auto, docker, or podman' >&2
    return 64
    ;;
  esac

  # This array is consumed by scripts that source this helper.
  # shellcheck disable=SC2034
  compose_cmd=("$container_engine" compose)
}

container_engine_os() {
  case "$container_engine" in
  docker)
    docker info --format '{{.OSType}}'
    ;;
  podman)
    podman info --format '{{.Host.OS}}'
    ;;
  *)
    printf '%s\n' 'ERROR: container engine has not been resolved' >&2
    return 70
    ;;
  esac
}

validate_compose_config() {
  case "$container_engine" in
  docker)
    "$@" config --quiet
    ;;
  podman)
    # podman-compose 1.0.x accepts config but not Docker's --quiet flag.
    "$@" config >/dev/null
    ;;
  *)
    printf '%s\n' 'ERROR: container engine has not been resolved' >&2
    return 70
    ;;
  esac
}
