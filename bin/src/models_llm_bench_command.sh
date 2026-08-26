panther_llm_bench() {
  local model="${args[model]}"
  panther_assert_loadable_llm "$model"

  local tokens runs log_path
  tokens="$(panther_resolve_option '--tokens' PANTHER_BENCH_TOKENS '256')"
  runs="$(panther_resolve_option '--runs' PANTHER_BENCH_RUNS '3')"
  log_path="$(panther_resolve_option '--log-path' PANTHER_BENCH_LOG_PATH "$PANTHER_REPO_ROOT/models/bench.log")"

  [[ "$tokens" -gt 0 ]] || panther_log_error '--tokens must be greater than zero.'
  [[ "$runs" -gt 0 ]] || panther_log_error '--runs must be greater than zero.'

  # A benchmark is only worth keeping if two invocations months apart are
  # comparable, so every degree of freedom is nailed down: a fixed prompt, a
  # fixed seed, greedy sampling, 'cache_prompt' off so prefill is measured
  # rather than replayed from the slot cache, and 'ignore_eos' on so the model
  # predicts exactly --tokens instead of stopping wherever it likes.
  local prompt='' sentence i
  sentence='Summarise the following requirement precisely and completely, without omitting any constraint. '
  for ((i = 0; i < 24; i++)); do
    prompt+="$sentence"
  done

  local request
  request="$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson tokens "$tokens" '{
    model: $model,
    messages: [{ role: "user", content: $prompt }],
    max_tokens: $tokens,
    temperature: 0,
    seed: 42,
    ignore_eos: true,
    cache_prompt: false,
    stream: false
  }')"

  panther_log_info "Benchmarking '$model': ${runs} run(s) of ${tokens} tokens after one discarded warm-up."

  local -a samples=()
  local run response timings
  for ((run = 0; run <= runs; run++)); do
    if [[ "$run" -eq 0 ]]; then
      panther_log_info 'Warm-up run (discarded); loads the model when it is not already resident.'
    else
      panther_log_info "Run ${run}/${runs}..."
    fi

    # The OpenAI-compatible path is deliberate: manager.js:499 only arbitrates
    # and preflights models for '/v1/chat/completions' and '/v1/completions'.
    # llama.cpp's native '/completion' would proxy through unclassified, so the
    # requested model might never be made resident.
    if ! response="$(curl -sS --insecure --max-time 900 -X POST 'https://localhost:8000/v1/chat/completions' \
      -H 'Content-Type: application/json' \
      -d "$request")"; then
      panther_log_error 'Cannot reach llama-manager at https://localhost:8000. Is the cluster running?'
    fi

    timings="$(jq -c '.timings // empty' <<<"$response" || true)"
    if [[ -z "$timings" ]]; then
      panther_log_error "No timings in response: $(jq -r '.error.message // tostring' <<<"$response" 2>/dev/null | head -1)"
    fi

    if [[ "$run" -gt 0 ]]; then
      samples+=("$timings")
    fi
  done

  # Median, not mean: one scheduling hiccup should not move the baseline.
  local summary
  summary="$(printf '%s\n' "${samples[@]}" | jq -s '
    def median: sort | if length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
    {
      decode: ([.[] | .predicted_per_second] | median),
      prefill: ([.[] | .prompt_per_second] | median),
      prompt_n: (.[0].prompt_n // 0),
      cached: ([.[] | .cache_n // 0] | add),
      draft_n: ([.[] | .draft_n // 0] | add),
      draft_accepted: ([.[] | .draft_n_accepted // 0] | add)
    }')"

  local decode prefill accept prompt_n cached
  decode="$(jq -r '.decode * 10 | round / 10' <<<"$summary")"
  prefill="$(jq -r '.prefill * 10 | round / 10' <<<"$summary")"
  accept="$(jq -r 'if .draft_n > 0 then ((.draft_accepted / .draft_n * 1000 | round / 10 | tostring) + "%") else "n/a" end' <<<"$summary")"
  prompt_n="$(jq -r '.prompt_n' <<<"$summary")"
  cached="$(jq -r '.cached' <<<"$summary")"

  if [[ "$cached" != '0' ]]; then
    panther_log_warn "Prompt cache served ${cached} token(s); prefill is understated for this entry."
  fi

  cd "$PANTHER_REPO_ROOT" || panther_log_error "Repository root $PANTHER_REPO_ROOT is unavailable."

  # The four things that moved under us during the 26.04 upgrade, recorded so a
  # future regression is a diff rather than an argument: host kernel, llama.cpp
  # commit, and the image ID that pins the ROCm user space and base image.
  local kernel llama_ref container image_id
  kernel="$(uname -r)"
  llama_ref="$(docker compose exec -T llama-cpp git -C /opt/llama-cpp rev-parse --short HEAD 2>/dev/null | tr -d '\r\n' || true)"
  [[ -n "$llama_ref" ]] || llama_ref='unknown'
  container="$(docker compose ps -q llama-cpp 2>/dev/null | head -1 || true)"
  image_id='unknown'
  if [[ -n "$container" ]]; then
    image_id="$(docker inspect --format '{{.Image}}' "$container" 2>/dev/null | cut -c8-19 || true)"
    [[ -n "$image_id" ]] || image_id='unknown'
  fi

  local previous=''
  if [[ -f "$log_path" ]]; then
    previous="$(awk -F'\t' -v m="$model" '$2 == m { line = $0 } END { print line }' "$log_path" || true)"
  else
    mkdir -p "$(dirname "$log_path")" || panther_log_error "Cannot create $(dirname "$log_path")."
    printf 'timestamp\tmodel\ttokens\truns\tdecode_tps\tprefill_tps\tdraft_accept\tkernel\tllama_ref\timage\n' >"$log_path"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$model" "$tokens" "$runs" \
    "$decode" "$prefill" "$accept" "$kernel" "$llama_ref" "$image_id" >>"$log_path"

  panther_log_success "decode ${decode} tok/s | prefill ${prefill} tok/s (${prompt_n} tokens) | draft accepted ${accept}"
  panther_log_info "kernel ${kernel} | llama.cpp ${llama_ref} | image ${image_id}"

  if [[ -n "$previous" ]]; then
    local previous_decode previous_stamp previous_ref delta regressed
    previous_stamp="$(cut -f1 <<<"$previous")"
    previous_decode="$(cut -f5 <<<"$previous")"
    previous_ref="$(cut -f9 <<<"$previous")"
    delta="$(awk -v a="$decode" -v b="$previous_decode" 'BEGIN { if (b + 0 == 0) { print "n/a"; exit } printf "%+.1f%%", (a - b) / b * 100 }')"
    regressed="$(awk -v a="$decode" -v b="$previous_decode" 'BEGIN { print (b + 0 > 0 && (a - b) / b * 100 <= -10) ? "yes" : "no" }')"

    if [[ "$regressed" == 'yes' ]]; then
      panther_log_warn "Decode ${delta} vs ${previous_stamp} (${previous_decode} tok/s, llama.cpp ${previous_ref}) - rebuild with the older ref to isolate llama.cpp from the platform."
    else
      panther_log_info "Decode ${delta} vs ${previous_stamp} (${previous_decode} tok/s, llama.cpp ${previous_ref})."
    fi
  else
    panther_log_info "Baseline recorded in ${log_path}; re-run after any kernel, driver, ROCm or llama.cpp change."
  fi
}

panther_llm_bench
