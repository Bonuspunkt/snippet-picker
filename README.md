# Snippet picker

A configurable odd-sized rofi carousel for copying text snippets (kaomoji, signatures, etc.). Default is 3×3:

```
[CURRENT CATEGORY]
[prev·prev] [prev snippet] [next·prev]
[prev cat]  [current snip] [next cat]
[prev·next] [next snippet] [next·next]
```

The highlight stays on the center cell; arrow keys move the items around it. Enter copies the current snippet and closes.

Larger grids (5×5, 7×7, …) show more neighbor categories/variants. Uneven sizes like `7x3` work too — both dimensions must be odd (even values are rounded up).

## Required packages

| Package | Role |
|---------|------|
| **rofi** | UI |
| **bash** | Scripts (needs associative arrays, bash 4+) |
| **gawk** / **awk** | Parse the snippet file |
| **wl-clipboard** | Clipboard on Wayland (`wl-copy`) |
| **xclip** or **xsel** | Clipboard on X11 (fallback) |
| **kdialog** | Optional “Copied” popup (KDE) |

### Install

Arch (package), from a clone that has tag `v0.1.0`:

```bash
makepkg -si
```

`makepkg -si` pulls in `rofi`, `gawk`, and `git`. Also install a clipboard helper and optionally the popup:

```bash
sudo pacman -S wl-clipboard xclip   # Wayland and/or X11
sudo pacman -S kdialog              # optional
```

Arch (deps only, run from the repo):

```bash
sudo pacman -S rofi wl-clipboard xclip
# optional:
sudo pacman -S kdialog
```

Debian / Ubuntu:

```bash
sudo apt install rofi wl-clipboard xclip
# optional:
sudo apt install kdialog
```

Fedora:

```bash
sudo dnf install rofi wl-clipboard xclip
# optional:
sudo dnf install kdialog
```

## Usage

```bash
./snippet-picker              # 3×3 (default)
GRID=5 ./snippet-picker       # 5×5
GRID=7x3 ./snippet-picker     # 7 cols × 3 rows
GRID_COLS=9 GRID_ROWS=5 ./snippet-picker
./snippet-picker --edit       # edit snippet file
```

| Key | Action |
|-----|--------|
| ← / → | Previous / next category (wraps) |
| ↑ / ↓ | Previous / next variant (wraps) |
| Enter | Copy current snippet and quit |
| Esc / click outside | Quit |

## Snippet file

Default path: `~/.config/kde-snippets/snippets.txt`

Override with `SNIPPET_FILE=/path/to/file`.

Format (one snippet per line):

```
Category::Label::Text
```

- No spaces in `Category` or `Label`
- Use `\n` for newlines in `Text`
- Lines starting with `#` are ignored

Example:

```
Shruggie::Classic::¯\_(ツ)_/¯
Signature::Formal::Best regards,\nYour Name
```

A starter file is created automatically on first run.
