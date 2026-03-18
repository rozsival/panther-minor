set -euo pipefail

declare -gr PANTHER_CLI_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cli"
declare -gr PANTHER_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
declare -gr PANTHER_MODELS_DIR="$PANTHER_REPO_ROOT/models"
declare -gr PANTHER_PROXY_DIR="$PANTHER_REPO_ROOT/proxy"
declare -gr PANTHER_ENV_FILE="$PANTHER_REPO_ROOT/.env"
declare -gr PANTHER_ENV_EXAMPLE_FILE="$PANTHER_REPO_ROOT/.env.example"
declare -gr PANTHER_SSHD_CONFIG="/etc/ssh/sshd_config"
declare -gr PANTHER_FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
