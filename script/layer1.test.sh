#!/usr/bin/env bash

set -Eeuo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root_dir"

bash script/start.test.sh
bash script/init-key.test.sh
bash script/download_futu_opend.test.sh
bash script/build_config.test.sh
bash script/compose.test.sh
bash script/live_readonly.test.sh
bash script/ci_config.test.sh
bash script/ci_gate.test.sh
