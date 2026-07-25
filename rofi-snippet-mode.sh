#!/usr/bin/env bash
# 3x3 snippet carousel backend.
# Category header always on top; cursor locked on center (current snippet).
# Middle-row sides = prev/next category names; corners = neighbor snippets.
# Arrows move items: Left/Right categories, Up/Down variants. Enter copies & quits.
set -euo pipefail

SNIPPET_FILE="${SNIPPET_FILE:-$HOME/.config/kde-snippets/snippets.txt}"
RETV="${ROFI_RETV:-0}"

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
    # Empty list → rofi quits
    exit 0
    ;;
esac

cat_idx=$(mod "$cat_idx" "$n_cat")
cur_cat="${categories[$cat_idx]}"
var_idx=$(wrap_var "$cur_cat" "$var_idx")

# Layout:
#   [CURRENT CATEGORY]                          <- message header
#   [prev·prev] [prev snippet] [next·prev]
#   [prev cat]  [current snip] [next cat]       <- cursor on center
#   [prev·next] [next snippet] [next·next]
printf '\0use-hot-keys\x1ftrue\n'
printf '\0no-custom\x1ftrue\n'
printf '\0message\x1f%s\n' "$cur_cat"
printf '\0data\x1f%s:%s\n' "$cat_idx" "$var_idx"
printf '\0keep-selection\x1ftrue\n'
printf '\0new-selection\x1f4\n'

emit_snip() {
  local c_name="$1" v_off="$2" selectable="${3:-0}"
  local n="${counts[$c_name]}"
  if [ "$n" -eq 0 ]; then
    printf 'empty\0display\x1f \x1fnonselectable\x1ftrue\n'
    return
  fi
  local v_i preview lbl
  v_i=$(wrap_var "$c_name" $((var_idx + v_off)))
  preview="${texts_of[$c_name:$v_i]}"
  lbl="${labels_of[$c_name:$v_i]}"
  if [ "$selectable" = 1 ]; then
    printf 'snip:%s:%s\0display\x1f%s\n' "$c_name" "$lbl" "$preview"
  else
    printf 'snip:%s:%s\0display\x1f%s\x1fnonselectable\x1ftrue\n' \
      "$c_name" "$lbl" "$preview"
  fi
}

emit_cat() {
  local c_name="$1"
  printf 'cat:%s\0display\x1f%s\x1fnonselectable\x1ftrue\n' "$c_name" "$c_name"
}

prev_i=$(mod $((cat_idx - 1)) "$n_cat")
next_i=$(mod $((cat_idx + 1)) "$n_cat")
prev_cat="${categories[$prev_i]}"
next_cat="${categories[$next_i]}"

# row: prev variants
emit_snip "$prev_cat" -1
emit_snip "$cur_cat" -1
emit_snip "$next_cat" -1
# row: category names | current snippet | category names
emit_cat "$prev_cat"
emit_snip "$cur_cat" 0 1
emit_cat "$next_cat"
# row: next variants
emit_snip "$prev_cat" 1
emit_snip "$cur_cat" 1
emit_snip "$next_cat" 1
