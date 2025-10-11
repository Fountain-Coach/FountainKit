#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_STAGE="v1"

print_usage() {
  cat <<'EOF'
Usage: lint-matrix.sh [--stage <version>] [--list] [spec ...]

Run Redocly lint checks against curated OpenAPI documents one spec at a time.

Options:
  --stage <version>  Stage directory under OpenAPI curation (default: v1)
  --list             Print the available lint tasks without executing them

Arguments:
  spec               Optional spec identifier(s). Use the basename (with or
                     without extension) such as "bootstrap" or
                     "semantic-browser". If omitted, all specs in the stage
                     are linted.

Environment:
  OPENAPI_LINT_CLI   Override the lint command (e.g., "redocly lint").

Examples:
  lint-matrix.sh --list
  lint-matrix.sh bootstrap planner
  lint-matrix.sh --stage v0 gateway
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
  esac
fi

STAGE="$DEFAULT_STAGE"
MODE="run"
declare -a REQUESTED_SPECS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      if [[ $# -lt 2 ]]; then
        echo "error: --stage requires a value" >&2
        exit 1
      fi
      STAGE="$2"
      shift 2
      ;;
    --list)
      MODE="list"
      shift
      ;;
    -*)
      echo "error: unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      REQUESTED_SPECS+=("$1")
      shift
      ;;
  esac
done

STAGE_DIR="$SCRIPT_DIR/$STAGE"
if [[ ! -d "$STAGE_DIR" ]]; then
  echo "error: stage directory not found: $STAGE_DIR" >&2
  exit 1
fi

SPEC_FILES=()
while IFS= read -r spec_file; do
  SPEC_FILES+=("$spec_file")
done < <(find "$STAGE_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
if [[ ${#SPEC_FILES[@]} -eq 0 ]]; then
  echo "error: no OpenAPI documents found under $STAGE_DIR" >&2
  exit 1
fi

TASK_LABELS=()
TASK_FILENAMES=()
TASK_PATHS=()

for spec_path in "${SPEC_FILES[@]}"; do
  filename="$(basename "$spec_path")"
  stem="${filename%.*}"
  TASK_LABELS+=("$stem")
  TASK_FILENAMES+=("$filename")
  TASK_PATHS+=("$spec_path")
done

resolve_spec_index() {
  local key="$1"
  local idx=0
  for label in "${TASK_LABELS[@]}"; do
    local fname="${TASK_FILENAMES[$idx]}"
    if [[ "$key" == "$label" || "$key" == "$fname" ]]; then
      echo "$idx"
      return 0
    fi
    idx=$((idx + 1))
  done
  return 1
}

select_specs() {
  if [[ ${#REQUESTED_SPECS[@]} -eq 0 ]]; then
    printf '%s\n' "${TASK_LABELS[@]}"
    return 0
  fi

  local resolved=()
  for key in "${REQUESTED_SPECS[@]}"; do
    if idx=$(resolve_spec_index "$key"); then
      resolved+=("${TASK_LABELS[$idx]}")
      continue
    fi
    echo "error: unknown spec identifier \"$key\"" >&2
    echo "       run with --list to see available options" >&2
    exit 1
  done
  printf '%s\n' "${resolved[@]}"
}

list_specs() {
  printf '%-24s %s\n' "Spec" "Path"
  printf '%-24s %s\n' "----" "----"
  local idx=0
  for label in "${TASK_LABELS[@]}"; do
    printf '%-24s %s\n' "$label" "${TASK_PATHS[$idx]}"
    idx=$((idx + 1))
  done
}

lint_command() {
  if [[ -n "${OPENAPI_LINT_CLI:-}" ]]; then
    printf '%s ' "$OPENAPI_LINT_CLI"
  else
    printf 'npx --yes @redocly/cli@1 lint '
  fi
}

run_lint() {
  local key="$1"
  if ! idx=$(resolve_spec_index "$key"); then
    echo "error: internal: unable to resolve spec \"$key\"" >&2
    return 1
  fi
  local spec_path="${TASK_PATHS[$idx]}"
  echo "==> Linting $key (${spec_path#$SCRIPT_DIR/})"
  if [[ -n "${OPENAPI_LINT_CLI:-}" ]]; then
    ${OPENAPI_LINT_CLI} "$spec_path"
  else
    npx --yes @redocly/cli@1 lint "$spec_path"
  fi
}

if [[ "$MODE" == "list" ]]; then
  list_specs
  exit 0
fi

selected_specs=()
while IFS= read -r item; do
  selected_specs+=("$item")
done < <(select_specs)

echo "OpenAPI lint task matrix (stage: $STAGE)"
echo "Command: $(lint_command)<spec>"
echo

overall_status=0
for spec_key in "${selected_specs[@]}"; do
  if ! run_lint "$spec_key"; then
    overall_status=1
  fi
  echo
done

exit "$overall_status"
