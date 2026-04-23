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

tf-in-cluster namespace="dev-system" path command="plan":
    ./scripts/verify/terraform-in-cluster.sh --namespace {{ namespace }} --path {{ path }} --command {{ command }}

zitadel-list-apps *names:
    ./scripts/verify/zitadel-list-apps.sh {{ names }}

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
