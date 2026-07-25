#!/usr/bin/env bash
# 3x3 snippet carousel: arrows wrap forever (Left/Right = category, Up/Down = variant)
# Requires: rofi, plus xclip/wl-clipboard for copying
set -euo pipefail

export LC_ALL=en_US.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE_SCRIPT="$SCRIPT_DIR/rofi-snippet-mode.sh"
SNIPPET_FILE="${SNIPPET_FILE:-$HOME/.config/kde-snippets/snippets.txt}"

mkdir -p "$(dirname "$SNIPPET_FILE")"

if [ ! -f "$SNIPPET_FILE" ]; then
  # Format: Category::Label::Text   (no spaces in Category or Label, please)
  cat > "$SNIPPET_FILE" <<'EOF'
Shruggie::Classic::¯\_(ツ)_/¯
Shruggie::Excited::ヽ(°〇°)ﾉ
Shruggie::Confused::¯\_(⊙_ʖ⊙)_/¯
Tableflip::Classic::(╯°□°)╯︵ ┻━┻
Tableflip::Return::┻━┻ ︵ ¯\(ツ)/¯ ︵ ┻━┻
Tableflip::Angry::(ノಠ益ಠ)ノ彡┻━┻
Signature::Formal::Best regards,\nYour Name
Signature::Casual::Cheers,\nYour Name
EOF
fi

if [ "${1:-}" = "--edit" ]; then
  for ed in kate kwrite xdg-open; do
    if command -v "$ed" >/dev/null 2>&1; then
      exec "$ed" "$SNIPPET_FILE"
    fi
  done
  echo "No editor found, edit manually: $SNIPPET_FILE"
  exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
  echo "rofi not found. Install it: sudo apt install rofi (or dnf/pacman equivalent)" >&2
  exit 1
fi

if ! awk -F'::' '!/^#/ && NF>=3 {found=1; exit} END{exit !found}' "$SNIPPET_FILE"; then
  echo "No snippets found in $SNIPPET_FILE" >&2
  exit 1
fi

SNIPPET_FILE="$SNIPPET_FILE" rofi \
  -modi "snippets:$MODE_SCRIPT" \
  -show snippets \
  -theme "$SCRIPT_DIR/snippet-picker.rasi" \
  -cycle \
  -kb-custom-1 Up \
  -kb-custom-2 Down \
  -kb-custom-3 Left \
  -kb-custom-4 Right \
  -kb-row-up "" \
  -kb-row-down "" \
  -kb-row-left "" \
  -kb-row-right "" \
  -kb-move-char-back Control+b \
  -kb-move-char-forward Control+f
