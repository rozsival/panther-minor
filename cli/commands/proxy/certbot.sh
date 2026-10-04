panther_proxy_certbot() {
  local domain="${args[--domain]}"
  local challenge_record="${args[--challenge-record]}"
  local credentials_file="$PANTHER_PROXY_DIR/acme/dns-credentials.json"
  local current_owner="$(id -u):$(id -g)"
  local force=false

  if ! mkdir -p "$PANTHER_PROXY_DIR/acme" "$PANTHER_PROXY_DIR/ssl"; then
    panther_log_error "Failed to create required directories under $PANTHER_PROXY_DIR"
  fi

  if [[ -n ${args[--force]+x} ]]; then
    read -r -p 'This will overwrite existing ACME DNS credentials. Are you sure? (y/n) ' -n 1 reply
    echo ''
    if [[ "$reply" =~ ^[Yy]$ ]]; then
      panther_log_info 'Forcing new acme-dns registration...'
      force=true
    else
      panther_log_info "Running without '--force'. Existing credentials will be used if available."
    fi
  fi

  local response username password fulldomain subdomain
  if [[ "$force" == true || ! -f "$credentials_file" ]]; then
    panther_log_info 'Registering with acme-dns...'
    response="$(curl -fsS -X POST https://auth.acme-dns.io/register)"
    [[ -n "$response" ]] || panther_log_error 'Empty response from acme-dns API.'

    username="$(echo "$response" | jq -r '.username')"
    password="$(echo "$response" | jq -r '.password')"
    fulldomain="$(echo "$response" | jq -r '.fulldomain')"
    subdomain="$(echo "$response" | jq -r '.subdomain')"

    if [[ "$username" == 'null' || -z "$username" ]]; then
      panther_log_error 'Failed to parse credentials.'
    fi

    printf '%s\n' "$response" >"$credentials_file"
    chmod 600 "$credentials_file"
    panther_log_success "Saved acme-dns credentials to $credentials_file."
  else
    panther_log_info "Using existing acme-dns credentials from $credentials_file."
    username="$(jq -r '.username' "$credentials_file")"
    password="$(jq -r '.password' "$credentials_file")"
    fulldomain="$(jq -r '.fulldomain' "$credentials_file")"
    subdomain="$(jq -r '.subdomain' "$credentials_file")"

    if [[ "$username" == 'null' || -z "$username" ]]; then
      panther_log_error "Invalid credentials file at $credentials_file. Run again with --force to register fresh acme-dns credentials."
    fi
  fi

  echo ''
  echo '=================================================================='
  echo 'ACTION REQUIRED: CREATE DNS CNAME RECORD'
  echo '=================================================================='
  echo "Record Name:  $challenge_record"
  echo 'Record Type:  CNAME'
  echo "Target:       $fulldomain"
  echo '=================================================================='
  echo ''
  # Pressing Enter here used to hand acme.sh a validation that could not succeed,
  # and Let's Encrypt allows only five failed validations per hostname per hour.
  # The CNAME is resolved through a recursive resolver first - the same path
  # Let's Encrypt takes - so a record saved in a zone that is not the delegated
  # one fails in seconds here instead of as an endless 'not valid yet' poll.
  local challenge_fqdn="_acme-challenge.${domain}"
  local resolved='' control control_resolved wildcard

  if ! command -v dig >/dev/null 2>&1; then
    panther_log_warn 'dig is unavailable, so the CNAME cannot be verified. Install bind9-dnsutils to enable this check.'
    read -r -p 'Press Enter to continue after DNS propagation...' || panther_log_error 'Aborted before issuance.'
  else
    while true; do
      read -r -p 'Press Enter once the record is saved to verify it...' || panther_log_error 'Aborted before the CNAME could be verified.'

      resolved="$(dig +short CNAME "$challenge_fqdn" @1.1.1.1 2>/dev/null | head -1 | sed 's/\.$//' || true)"
      if [[ -z "$resolved" ]]; then
        resolved="$(dig +short CNAME "$challenge_fqdn" 2>/dev/null | head -1 | sed 's/\.$//' || true)"
      fi

      # A wildcard record answers for names that do not exist, which makes an
      # absent challenge record look like a wrong target instead. This zone
      # class is common, so a control lookup for a name nobody would ever
      # create separates real answers from synthesised ones.
      wildcard=false
      control="_panther-preflight-${RANDOM}.${domain}"
      control_resolved="$(dig +short CNAME "$control" @1.1.1.1 2>/dev/null | head -1 | sed 's/\.$//' || true)"
      if [[ -n "$resolved" && "$resolved" == "$control_resolved" ]]; then
        resolved=''
        wildcard=true
      fi

      if [[ "$resolved" == "$fulldomain" ]]; then
        panther_log_success "$challenge_fqdn resolves to $fulldomain."
        break
      fi

      if [[ -z "$resolved" ]]; then
        panther_log_warn "$challenge_fqdn does not resolve."
        if [[ "$wildcard" == true ]]; then
          echo '  A wildcard in the zone answers for every name, so the record is absent rather than misdirected.'
        fi
        echo '  If the record looks correct in your DNS panel, the zone you edited may not be the delegated one. Compare:'
        echo "    dig +short NS ${domain#*.}"
        echo '  against the nameservers your registrar publishes. A record in an undelegated zone never resolves.'
      else
        panther_log_warn "$challenge_fqdn points at '$resolved', expected '$fulldomain'."
        echo '  A stale target usually means acme-dns was re-registered with --force after the record was created.'
      fi
    done
  fi

  panther_log_info 'Issuing certificate...'
  local issue_args=(--issue --dns dns_acmedns -d "$domain" --server letsencrypt)
  if [[ "$force" == true ]]; then
    issue_args+=(--force)
  fi

  docker run --rm -it \
    --user "$current_owner" \
    -v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
    -e ACMEDNS_UPDATE_URL='https://auth.acme-dns.io/update' \
    -e ACMEDNS_USERNAME="$username" \
    -e ACMEDNS_PASSWORD="$password" \
    -e ACMEDNS_SUBDOMAIN="$subdomain" \
    neilpang/acme.sh "${issue_args[@]}"

  panther_log_info 'Installing certificate to SSL directory...'
  docker run --rm -it \
    --user "$current_owner" \
    -v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
    -v "$PANTHER_PROXY_DIR/ssl:/ssl" \
    neilpang/acme.sh --install-cert -d "$domain" \
    --key-file /ssl/privkey.pem \
    --fullchain-file /ssl/fullchain.pem

  panther_log_info "Ensuring host file ownership for current user ($current_owner)..."
  docker run --rm \
    -v "$PANTHER_PROXY_DIR/acme:/acme.sh" \
    -v "$PANTHER_PROXY_DIR/ssl:/ssl" \
    alpine:3.22 sh -c "chown -R $current_owner /acme.sh /ssl"

  panther_log_success 'Certificate provisioning completed.'
}

panther_proxy_certbot
