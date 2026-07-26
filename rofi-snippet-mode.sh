#!/usr/bin/env bash
# NxM snippet carousel backend (odd dims; default 3x3).
# Category header on top; cursor locked on center (current snippet).
# Middle-row sides = category names; all other cells = neighbor snippets.
# Arrows move items: Left/Right categories, Up/Down variants. Enter copies & quits.
#
# Grid size from env (exported by launcher) or GRID / GRID_COLS / GRID_ROWS.
set -euo pipefail

SNIPPET_FILE="${SNIPPET_FILE:-$HOME/.config/snippet-picker/snippets.txt}"
RETV="${ROFI_RETV:-0}"

# --- grid size (odd cols x odd rows) ---
parse_grid() {
  local raw="${GRID:-}" cols rows
  if [[ -n "${GRID_COLS:-}" || -n "${GRID_ROWS:-}" ]]; then
    cols="${GRID_COLS:-3}"
    rows="${GRID_ROWS:-${cols}}"
  elif [[ "$raw" =~ ^([0-9]+)[xX]([0-9]+)$ ]]; then
    cols="${BASH_REMATCH[1]}"
    rows="${BASH_REMATCH[2]}"
  elif [[ "$raw" =~ ^([0-9]+)$ ]]; then
    cols="${BASH_REMATCH[1]}"
    rows="$cols"
  else
    cols=3
    rows=3
  fi
  # force odd (round up), clamp 1..15
  (( cols % 2 == 0 )) && cols=$((cols + 1))
  (( rows % 2 == 0 )) && rows=$((rows + 1))
  (( cols < 1 )) && cols=1
  (( rows < 1 )) && rows=1
  (( cols > 15 )) && cols=15
  (( rows > 15 )) && rows=15
  GRID_COLS=$cols
  GRID_ROWS=$rows
}
parse_grid

copy_text() {
  local text="$1"
  if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$text" | wl-copy || true
  elif command -v xclip >/dev/null 2>&1; then
    printf '%s' "$text" | xclip -selection clipboard || true
  elif command -v xsel >/dev/null 2>&1; then
    printf '%s' "$text" | xsel --clipboard --input || true
  fi
}

# Strip shell-metacharacters before interpolating into kdialog argv.
sanitize_popup_label_inplace() {
  local -n _s="$1"
  _s="${_s//$/}"
  _s="${_s//\`/}"
  _s="${_s//\"/}"
  _s="${_s//\\/}"
  _s="${_s//$'\n'/}"
}

# Load snippets (Category/Label = [[:alnum:]_-]+). Prefer cache keyed by file identity.
declare -A labels_of texts_of raws_of counts
categories=()

_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/snippet-picker"
_fp="$(stat -c '%d:%i:%s:%Y' "$SNIPPET_FILE" 2>/dev/null || true)"
_cache_file=""
if [[ -n "$_fp" ]] && mkdir -p "$_cache_dir" 2>/dev/null; then
  _cache_file="$_cache_dir/snippets-$UID-${_fp//:/_}.bash"
fi

_load_from_file() {
  local _cat _lbl _prev _raw _i
  declare -A _cat_seen
  categories=()
  labels_of=()
  texts_of=()
  raws_of=()
  counts=()
  while IFS= read -r -d '' _cat &&
        IFS= read -r -d '' _lbl &&
        IFS= read -r -d '' _prev &&
        IFS= read -r -d '' _raw; do
    if [[ -z "${_cat_seen[$_cat]:-}" ]]; then
      _cat_seen["$_cat"]=1
      categories+=("$_cat")
      counts["$_cat"]=0
    fi
    _i="${counts[$_cat]}"
    labels_of["$_cat:$_i"]="$_lbl"
    texts_of["$_cat:$_i"]="$_prev"
    raws_of["$_cat:$_i"]="$_raw"
    counts["$_cat"]=$((_i + 1))
  done < <(awk -F'::' '
    !/^#/ && NF >= 3 && $1 ~ /^[[:alnum:]_-]+$/ && $2 ~ /^[[:alnum:]_-]+$/ {
      cat = $1; lbl = $2
      sub(/^[^:]*::[^:]*::/, "")
      raw = $0
      prev = $0
      gsub(/\\n/, " ⏎ ", prev)
      gsub(/\0/, "", prev); gsub(/\x1f/, "", prev); gsub(/\x1e/, "", prev)
      gsub(/\0/, "", raw)
      printf "%s\0%s\0%s\0%s\0", cat, lbl, prev, raw
    }' "$SNIPPET_FILE")
}

_write_cache() {
  local c i n
  {
    printf 'categories=('
    for c in "${categories[@]}"; do printf '%q ' "$c"; done
    printf ')\n'
    echo 'declare -A labels_of texts_of raws_of counts'
    for c in "${categories[@]}"; do
      printf 'counts[%q]=%q\n' "$c" "${counts[$c]}"
      n="${counts[$c]}"
      for ((i = 0; i < n; i++)); do
        printf 'labels_of[%q]=%q\n' "$c:$i" "${labels_of[$c:$i]}"
        printf 'texts_of[%q]=%q\n' "$c:$i" "${texts_of[$c:$i]}"
        printf 'raws_of[%q]=%q\n' "$c:$i" "${raws_of[$c:$i]}"
      done
    done
  } >"${_cache_file}.tmp" && mv -f "${_cache_file}.tmp" "$_cache_file"
  # Drop stale fingerprints for this uid (best-effort).
  find "$_cache_dir" -maxdepth 1 -type f -name "snippets-$UID-*.bash" ! -name "$(basename "$_cache_file")" -delete 2>/dev/null || true
}

if [[ -n "$_cache_file" && -f "$_cache_file" ]]; then
  # Cache is written only by us with printf %q; fingerprint ties it to this file version.
  # shellcheck disable=SC1090
  source "$_cache_file"
else
  _load_from_file
  if [[ -n "$_cache_file" && ${#categories[@]} -gt 0 ]]; then
    _write_cache || true
  fi
fi
unset _cache_dir _fp _cache_file

n_cat="${#categories[@]}"
if [ "$n_cat" -eq 0 ]; then
  echo "No snippets found in $SNIPPET_FILE" >&2
  exit 1
fi

# State: cat_idx:var_idx
IFS=':' read -r cat_idx var_idx <<<"${ROFI_DATA:-0:0}"
cat_idx="${cat_idx:-0}"
var_idx="${var_idx:-0}"
[[ "$cat_idx" =~ ^[0-9]+$ ]] || cat_idx=0
[[ "$var_idx" =~ ^[0-9]+$ ]] || var_idx=0

# Modulo into destination variable (no command-substitution subshell).
mod_into() {
  # shellcheck disable=SC2034
  printf -v "$1" '%s' $(( ($2 % $3 + $3) % $3 ))
}

wrap_var_into() {
  local _n="${counts[$2]}"
  if [ "$_n" -le 0 ]; then
    printf -v "$1" '0'
    return
  fi
  mod_into "$1" "$3" "$_n"
}

# Custom keys: 10=Up 11=Down 12=Left 13=Right (kb-custom-1..4)
case "$RETV" in
  10) var_idx=$((var_idx - 1)) ;;
  11) var_idx=$((var_idx + 1)) ;;
  12) cat_idx=$((cat_idx - 1)) ;;
  13) cat_idx=$((cat_idx + 1)) ;;
  1)
    mod_into cat_idx "$cat_idx" "$n_cat"
    cur_cat="${categories[$cat_idx]}"
    wrap_var_into var_idx "$cur_cat" "$var_idx"
    lbl="${labels_of[$cur_cat:$var_idx]}"
    text="${raws_of[$cur_cat:$var_idx]}"
    text="${text//\\n/$'\n'}"
    copy_text "$text"
    if command -v kdialog >/dev/null 2>&1; then
      _popup_lbl="$lbl"
      sanitize_popup_label_inplace _popup_lbl
      kdialog --passivepopup "Copied: ${_popup_lbl}" 2 >/dev/null || true
      unset _popup_lbl
    fi
    exit 0
    ;;
esac

mod_into cat_idx "$cat_idx" "$n_cat"
cur_cat="${categories[$cat_idx]}"
wrap_var_into var_idx "$cur_cat" "$var_idx"

half_c=$(( GRID_COLS / 2 ))
half_r=$(( GRID_ROWS / 2 ))
# Center cell index in row-major order
center_idx=$(( half_r * GRID_COLS + half_c ))

# Row delim = RS (0x1e) so display text may contain real \n for two-line cells.
# Only set on first call (rofi remembers it). The delim option line itself must
# still end with the *old* delimiter (\n). Value uses rofi's \xNN escape form.
D=$'\x1e'
if [[ "${RETV}" == "0" ]]; then
  printf '\0delim\x1f\\x1e\n'
fi

# Middle-row side cells (categories) → urgent, for distinct theming.
urgent_idxs=()
for (( dx = -half_c; dx <= half_c; dx++ )); do
  if [ "$dx" -ne 0 ]; then
    urgent_idxs+=( $(( half_r * GRID_COLS + dx + half_c )) )
  fi
done
urgent_csv=$(IFS=,; echo "${urgent_idxs[*]}")

# Categories are already safe IDs — no further sanitize needed.
printf '\0use-hot-keys\x1ftrue%s' "$D"
printf '\0no-custom\x1ftrue%s' "$D"
printf '\0message\x1f%s%s' "$cur_cat" "$D"
printf '\0data\x1f%s:%s%s' "$cat_idx" "$var_idx" "$D"
printf '\0keep-selection\x1ftrue%s' "$D"
printf '\0new-selection\x1f%s%s' "$center_idx" "$D"
[ -n "$urgent_csv" ] && printf '\0urgent\x1f%s%s' "$urgent_csv" "$D"

# Two-line cell into destination var (preview already sanitized at load).
cell_display_into() {
  local icon="$2" name="$3"
  icon="${icon//$'\n'/ }"
  name="${name//$'\n'/ }"
  printf -v "$1" '%s\n%s' "$icon" "$name"
}

emit_snip() {
  local c_name="$1" v_off="$2" selectable="${3:-0}"
  local n="${counts[$c_name]}"
  if [ "$n" -eq 0 ]; then
    printf 'empty\0display\x1f \x1fnonselectable\x1ftrue%s' "$D"
    return
  fi
  local v_i preview lbl disp
  wrap_var_into v_i "$c_name" $((var_idx + v_off))
  preview="${texts_of[$c_name:$v_i]}"
  lbl="${labels_of[$c_name:$v_i]}"
  cell_display_into disp "$preview" "$lbl"
  if [ "$selectable" = 1 ]; then
    printf 'snip:%s:%s\0display\x1f%s%s' "$c_name" "$lbl" "$disp" "$D"
  else
    printf 'snip:%s:%s\0display\x1f%s\x1fnonselectable\x1ftrue%s' \
      "$c_name" "$lbl" "$disp" "$D"
  fi
}

emit_cat() {
  local c_name="$1"
  local n="${counts[$c_name]}" icon="·" disp v_i
  if [ "$n" -gt 0 ]; then
    wrap_var_into v_i "$c_name" "$var_idx"
    icon="${texts_of[$c_name:$v_i]}"
  fi
  cell_display_into disp "$icon" "$c_name"
  printf 'cat:%s\0display\x1f%s\x1fnonselectable\x1ftrue%s' "$c_name" "$disp" "$D"
}

# Emit GRID_ROWS x GRID_COLS neighborhood (row-major, flow horizontal).
# Middle row (dy=0): category names on sides, current snippet in center.
# Other rows: snippets at (cat+dx, var+dy).
for (( dy = -half_r; dy <= half_r; dy++ )); do
  for (( dx = -half_c; dx <= half_c; dx++ )); do
    mod_into c_i $((cat_idx + dx)) "$n_cat"
    c_name="${categories[$c_i]}"

    if [ "$dx" -eq 0 ] && [ "$dy" -eq 0 ]; then
      emit_snip "$c_name" 0 1
    elif [ "$dy" -eq 0 ]; then
      emit_cat "$c_name"
    else
      emit_snip "$c_name" "$dy"
    fi
  done
done
