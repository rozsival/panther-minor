panther_llm_bench() {
  local model="${args[model]}"
  panther_assert_loadable_llm "$model"

  local tokens runs warmups loads log_path
  tokens="$(panther_resolve_option '--tokens' PANTHER_BENCH_TOKENS '256')"
  runs="$(panther_resolve_option '--runs' PANTHER_BENCH_RUNS '3')"
  warmups="$(panther_resolve_option '--warmups' PANTHER_BENCH_WARMUPS '8')"
  loads="$(panther_resolve_option '--loads' PANTHER_BENCH_LOADS '1')"
  log_path="$(panther_resolve_option '--log-path' PANTHER_BENCH_LOG_PATH "$PANTHER_REPO_ROOT/models/bench.log")"

  [[ "$tokens" -gt 0 ]] || panther_log_error '--tokens must be greater than zero.'
  [[ "$runs" -gt 0 ]] || panther_log_error '--runs must be greater than zero.'
  [[ "$warmups" -ge 0 ]] || panther_log_error '--warmups cannot be negative.'
  [[ "$loads" -gt 0 ]] || panther_log_error '--loads must be greater than zero.'

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

  # Throughput ramps for roughly seven requests after a model becomes resident, so a single
  # discarded warm-up measures the ramp rather than the steady state: 8 warm-ups converge, 1 warm-up
  # under-reported this stack by 54%. Separately, each llama-server process settles into one of a few
  # discrete throughput modes that vary up to 1.45x between loads while being stable to within 1%
  # inside a load, so a single load cannot resolve anything smaller than ~25%. --loads > 1 restarts
  # llama-cpp between loads and reports the median of the per-load medians.
  local median_filter
  median_filter='def median: sort | if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;'

  panther_bench_sample() {
    local response timings
    if ! response="$(curl -sS --insecure --max-time 900 -X POST 'https://localhost:8000/v1/chat/completions' \
      -H 'Content-Type: application/json' \
      -d "$request")"; then
      panther_log_error 'Cannot reach llama-manager at https://localhost:8000. Is the cluster running?'
    fi

    # The OpenAI-compatible path is deliberate: manager.js:499 only arbitrates
    # and preflights models for '/v1/chat/completions' and '/v1/completions'.
    # llama.cpp's native '/completion' would proxy through unclassified, so the
    # requested model might never be made resident.
    timings="$(jq -c '.timings // empty' <<<"$response" || true)"
    if [[ -z "$timings" ]]; then
      panther_log_error "No timings in response: $(jq -r '.error.message // tostring' <<<"$response" 2>/dev/null | head -1)"
    fi

    printf '%s\n' "$timings"
  }

  panther_log_info "Benchmarking '$model': ${loads} load(s) x ${runs} run(s) of ${tokens} tokens after ${warmups} discarded warm-up(s)."

  local -a samples=() load_medians=()
  local load run failure load_median
  for ((load = 1; load <= loads; load++)); do
    if ((load > 1)); then
      panther_log_info "Restarting llama-cpp for load ${load}/${loads}; a fresh process re-rolls its throughput mode."
      panther_compose restart llama-cpp >/dev/null 2>&1 || panther_log_error 'Could not restart llama-cpp.'
      panther_await_service_health llama-cpp 300 || panther_log_error 'llama-cpp did not report healthy after the restart.'
    fi

    if ! failure="$(panther_llm_request_load "$model")"; then
      panther_log_error "Failed to load model '$model'. $failure"
    fi

    for ((run = 1; run <= warmups; run++)); do
      panther_log_info "Load ${load}/${loads} warm-up ${run}/${warmups} (discarded)..."
      panther_bench_sample >/dev/null
    done

    local -a load_samples=()
    local timings
    for ((run = 1; run <= runs; run++)); do
      panther_log_info "Load ${load}/${loads} run ${run}/${runs}..."
      timings="$(panther_bench_sample)"
      load_samples+=("$timings")
      samples+=("$timings")
    done

    load_median="$(printf '%s\n' "${load_samples[@]}" | jq -s "$median_filter"' ([.[] | .predicted_per_second] | median)')"
    load_medians+=("$load_median")
    panther_log_info "Load ${load}/${loads} median decode $(jq -rn --argjson v "$load_median" '$v * 10 | round / 10') tok/s."
  done

  # Median, not mean: one scheduling hiccup should not move the baseline. With several loads the
  # median is taken over the per-load medians, so one unlucky mode cannot claim to be the machine.
  local summary
  summary="$(printf '%s\n' "${samples[@]}" | jq -s --argjson medians "$(printf '%s\n' "${load_medians[@]}" | jq -s '.')" "$median_filter"'
    {
      decode: ($medians | median),
      spread: (if ($medians | length) > 1 then $medians else [.[] | .predicted_per_second] end
               | (max - min) / (. | median) * 100),
      prefill: ([.[] | .prompt_per_second] | median),
      prompt_n: (.[0].prompt_n // 0),
      cached: ([.[] | .cache_n // 0] | add),
      draft_n: ([.[] | .draft_n // 0] | add),
      draft_accepted: ([.[] | .draft_n_accepted // 0] | add)
    }')"

  local decode prefill accept prompt_n cached spread
  decode="$(jq -r '.decode * 10 | round / 10' <<<"$summary")"
  prefill="$(jq -r '.prefill * 10 | round / 10' <<<"$summary")"
  spread="$(jq -r '.spread | round' <<<"$summary")"
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
    printf 'timestamp\tmodel\ttokens\truns\tdecode_tps\tprefill_tps\tdraft_accept\tkernel\tllama_ref\timage\twarmups\tloads\tspread_pct\n' >"$log_path"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$model" "$tokens" "$runs" \
    "$decode" "$prefill" "$accept" "$kernel" "$llama_ref" "$image_id" \
    "$warmups" "$loads" "$spread" >>"$log_path"

  panther_log_success "decode ${decode} tok/s | prefill ${prefill} tok/s (${prompt_n} tokens) | draft accepted ${accept}"
  panther_log_info "kernel ${kernel} | llama.cpp ${llama_ref} | image ${image_id}"

  # A spread this wide means the number above is one draw from a distribution, not a measurement.
  if [[ "$spread" -ge 10 ]]; then
    if [[ "$loads" -gt 1 ]]; then
      panther_log_warn "Per-load medians spread ${spread}%; this stack has discrete throughput modes, so treat differences below that as unresolved."
    else
      panther_log_warn "Run spread ${spread}%; re-run with --loads 3 to separate a real change from the load-to-load mode lottery."
    fi
  elif [[ "$loads" -eq 1 ]]; then
    panther_log_info 'Single load measured; --loads 3 is the minimum that survives the mode lottery when comparing presets.'
  fi

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
