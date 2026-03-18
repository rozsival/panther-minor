validate_port() {
	if [[ ! "$1" =~ ^[0-9]+$ ]]; then
		echo 'must be an integer'
		return
	fi

	if (( $1 < 1 || $1 > 65535 )); then
		echo 'must be between 1 and 65535'
	fi
}
