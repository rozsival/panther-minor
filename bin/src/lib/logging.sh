panther_log_info() {
  echo -e "\033[0;34m[INFO]\033[0m  $*"
}
panther_log_success() {
  echo -e "\033[0;32m[OK]\033[0m    $*"
}
panther_log_warn() {
  echo -e "\033[1;33m[WARN]\033[0m  $*"
}
panther_log_error() {
  echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
  exit 1
}
