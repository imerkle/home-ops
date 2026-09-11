set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

# bootstrap new cluster from scratch
mod bootstrap "bootstrap"
# manage talos cluster
mod talos "talos"
# manage kubernetes cluster
mod kube "kubernetes"

cluster := shell("if [ -s " + justfile_dir() + "/.current-cluster ] && [ \"$(cat " + justfile_dir() + "/.current-cluster)\" != \"nodes\" ]; then cat " + justfile_dir() + "/.current-cluster; else echo .; fi")
[private]
default:
    just -l

# tf-in-cluster namespace="dev-system" path command="plan":
#     ./scripts/verify/terraform-in-cluster.sh --namespace {{ namespace }} --path {{ path }} --command {{ command }}

zitadel-list-apps *names:
    ./scripts/verify/zitadel-list-apps.sh {{ names }}

# Run declarative k6 load test in cluster for a service (options: --build <id>, --local)
loadtest service *args:
    @dir="$(find "{{ justfile_dir() }}/kubernetes/apps" -type d -path "*/{{ service }}/loadtests" | head -n 1)"; \
    if [[ -z "$dir" ]]; then \
        echo "[-] Error: No loadtests found for '{{ service }}' under kubernetes/apps/**/{{ service }}/loadtests" >&2; \
        exit 1; \
    fi; \
    build_id="latest"; \
    prev=""; \
    for arg in {{ args }}; do \
        if [[ "$prev" == "--build" || "$prev" == "-b" ]]; then \
            build_id="$arg"; \
        fi; \
        prev="$arg"; \
    done; \
    if [[ "{{ args }}" == *"--local"* ]]; then \
        echo "[+] Running local k6 load test for {{ service }} (build: $build_id)..."; \
        TARGET_URL="${TARGET_URL:-https://thumb.x3y.space}" \
        K6_PROMETHEUS_RW_SERVER_URL="${K6_PROMETHEUS_RW_SERVER_URL:-https://prometheus.x3y.space/api/v1/write}" \
        BUILD_ID="$build_id" k6 run --tag testid="{{ service }}" --tag app="{{ service }}" --tag build="$build_id" -o experimental-prometheus-rw "$dir/test.js"; \
    else \
        ns="$(yq -r '.metadata.namespace // "default"' "$dir/testrun.yaml")"; \
        name="$(yq -r '.metadata.name' "$dir/testrun.yaml")"; \
        echo "[+] Resetting previous TestRun '$name' in namespace '$ns'..."; \
        kubectl delete -k "$dir" --ignore-not-found=true --wait=false; \
        sleep 1; \
        echo "[+] Launching declarative TestRun '$name' (build: $build_id)..."; \
        kubectl kustomize "$dir" | sed "s/value: \"latest\"/value: \"$build_id\"/g" | kubectl apply -f -; \
        echo "[+] Single-App Dashboard: https://grafana.x3y.space/d/ccbb2351-2ae2-462f-ae0e-f2c893ad1028/k6-prometheus?var-testid={{ service }}"; \
        echo "[+] Build Comparison:   https://grafana.x3y.space/d/k6-build-comparison/k6-build-performance-comparison?var-testid={{ service }}"; \
        echo "[+] Waiting for runners to initialize..."; \
        sleep 4; \
        kubectl get testrun -n "$ns" "$name" 2>/dev/null || true; \
        echo "[+] Tailing runner logs (Ctrl+C to detach; test continues in cluster)..."; \
        kubectl logs -n "$ns" -l "k6_cr=$name" -f --tail=30 2>/dev/null || true; \
    fi


[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
template context file *args:
    if command -v envconsul >/dev/null && command -v minijinja-cli >/dev/null; then \
        envconsul -secret="{{ cluster }}/{{ context }}" -once -no-prefix minijinja-cli --strict "{{ file }}" {{ args }} 2> /dev/null; \
    else \
        echo "missing required templating tools: envconsul and/or minijinja-cli" >&2; \
        exit 127; \
    fi

cluster:
  dirs="$(find "{{ justfile_dir() }}/talos" -mindepth 1 -maxdepth 1 -type d ! -name nodes | sed 's@.*/@@g')"; \
  if [[ -z "$dirs" ]]; then \
    echo -n "." > "{{ justfile_dir() }}/.current-cluster"; \
  else \
    echo -n "$(printf '%s\n' "$dirs" | gum choose --header 'Cluster?')" > "{{ justfile_dir() }}/.current-cluster"; \
  fi
  cat "{{ justfile_dir() }}/.current-cluster"
  direnv reload
