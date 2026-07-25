#!/usr/bin/env bash
# NxM snippet carousel backend (odd dims; default 3x3).
# Category header on top; cursor locked on center (current snippet).
# Middle-row sides = category names; all other cells = neighbor snippets.
# Arrows move items: Left/Right categories, Up/Down variants. Enter copies & quits.
#
# Grid size from GRID (e.g. 5, 5x5, 7x3) or GRID_COLS / GRID_ROWS (odd integers).
set -euo pipefail

SNIPPET_FILE="${SNIPPET_FILE:-$HOME/.config/kde-snippets/snippets.txt}"
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

# Load categories (file order, unique) and variants per category.
mapfile -t categories < <(awk -F'::' '!/^#/ && NF>=3 {print $1}' "$SNIPPET_FILE" | awk '!seen[$0]++')
n_cat="${#categories[@]}"
if [ "$n_cat" -eq 0 ]; then
  echo "No snippets found in $SNIPPET_FILE" >&2
  exit 1
fi

declare -A labels_of texts_of counts
for cat in "${categories[@]}"; do
  mapfile -t _lbls < <(awk -F'::' -v c="$cat" '$1==c {print $2}' "$SNIPPET_FILE")
  mapfile -t _txts < <(awk -F'::' -v c="$cat" '
    $1==c {
      sub(/^[^:]*::[^:]*::/, "")
      gsub(/\\n/, " ⏎ ")
      print
    }' "$SNIPPET_FILE")
  counts["$cat"]="${#_lbls[@]}"
  for i in "${!_lbls[@]}"; do
    labels_of["$cat:$i"]="${_lbls[$i]}"
    texts_of["$cat:$i"]="${_txts[$i]}"
  done
done

raw_text() {
  local cat="$1" lbl="$2"
  awk -F'::' -v c="$cat" -v l="$lbl" \
    '$1==c && $2==l { sub(/^[^:]*::[^:]*::/,""); print; exit }' "$SNIPPET_FILE"
}

# State: cat_idx:var_idx
IFS=':' read -r cat_idx var_idx <<<"${ROFI_DATA:-0:0}"
cat_idx="${cat_idx:-0}"
var_idx="${var_idx:-0}"
[[ "$cat_idx" =~ ^[0-9]+$ ]] || cat_idx=0
[[ "$var_idx" =~ ^[0-9]+$ ]] || var_idx=0
cat_idx=$((cat_idx % n_cat))

mod() {
  local m=$(( ($1 % $2 + $2) % $2 ))
  printf '%s' "$m"
}

wrap_var() {
  local cat="$1" idx="$2"
  local n="${counts[$cat]}"
  [ "$n" -gt 0 ] || { printf '0'; return; }
  mod "$idx" "$n"
}

# Custom keys: 10=Up 11=Down 12=Left 13=Right (kb-custom-1..4)
case "$RETV" in
  10) var_idx=$((var_idx - 1)) ;;
  11) var_idx=$((var_idx + 1)) ;;
  12) cat_idx=$((cat_idx - 1)) ;;
  13) cat_idx=$((cat_idx + 1)) ;;
  1)
    cat_idx=$(mod "$cat_idx" "$n_cat")
    cur_cat="${categories[$cat_idx]}"
    var_idx=$(wrap_var "$cur_cat" "$var_idx")
    lbl="${labels_of[$cur_cat:$var_idx]}"
    text="$(raw_text "$cur_cat" "$lbl")"
    text="${text//\\n/$'\n'}"
    copy_text "$text"
    command -v kdialog >/dev/null 2>&1 && kdialog --passivepopup "Copied: $lbl" 2 >/dev/null || true
    exit 0
    ;;
esac

cat_idx=$(mod "$cat_idx" "$n_cat")
cur_cat="${categories[$cat_idx]}"
var_idx=$(wrap_var "$cur_cat" "$var_idx")

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

printf '\0use-hot-keys\x1ftrue%s' "$D"
printf '\0no-custom\x1ftrue%s' "$D"
printf '\0message\x1f%s%s' "$cur_cat" "$D"
printf '\0data\x1f%s:%s%s' "$cat_idx" "$var_idx" "$D"
printf '\0keep-selection\x1ftrue%s' "$D"
printf '\0new-selection\x1f%s%s' "$center_idx" "$D"
[ -n "$urgent_csv" ] && printf '\0urgent\x1f%s%s' "$urgent_csv" "$D"

# Two-line cell: icon above, label below (launcher passes -eh 2).
cell_display() {
  local icon="$1" name="$2"
  icon="${icon//$'\n'/ }"
  name="${name//$'\n'/ }"
  printf '%s\n%s' "$icon" "$name"
}

emit_snip() {
  local c_name="$1" v_off="$2" selectable="${3:-0}"
  local n="${counts[$c_name]}"
  if [ "$n" -eq 0 ]; then
    printf 'empty\0display\x1f \x1fnonselectable\x1ftrue%s' "$D"
    return
  fi
  local v_i preview lbl disp
  v_i=$(wrap_var "$c_name" $((var_idx + v_off)))
  preview="${texts_of[$c_name:$v_i]}"
  lbl="${labels_of[$c_name:$v_i]}"
  disp=$(cell_display "$preview" "$lbl")
  if [ "$selectable" = 1 ]; then
    printf 'snip:%s:%s\0display\x1f%s%s' "$c_name" "$lbl" "$disp" "$D"
  else
    printf 'snip:%s:%s\0display\x1f%s\x1fnonselectable\x1ftrue%s' \
      "$c_name" "$lbl" "$disp" "$D"
  fi
}

emit_cat() {
  local c_name="$1"
  local n="${counts[$c_name]}" icon="·" disp
  if [ "$n" -gt 0 ]; then
    local v_i
    v_i=$(wrap_var "$c_name" "$var_idx")
    icon="${texts_of[$c_name:$v_i]}"
  fi
  disp=$(cell_display "$icon" "$c_name")
  printf 'cat:%s\0display\x1f%s\x1fnonselectable\x1ftrue%s' "$c_name" "$disp" "$D"
}

# Emit GRID_ROWS x GRID_COLS neighborhood (row-major, flow horizontal).
# Middle row (dy=0): category names on sides, current snippet in center.
# Other rows: snippets at (cat+dx, var+dy).
for (( dy = -half_r; dy <= half_r; dy++ )); do
  for (( dx = -half_c; dx <= half_c; dx++ )); do
    c_i=$(mod $((cat_idx + dx)) "$n_cat")
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
