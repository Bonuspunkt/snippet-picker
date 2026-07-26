# Maintainer: Bonuspunkt
pkgname=snippet-picker
pkgver=0.3.0
pkgrel=1
pkgdesc='Configurable odd-sized rofi carousel for copying text snippets'
arch=('any')
url='https://github.com/Bonuspunkt/snippet-picker'
license=('Unlicense')
depends=('bash' 'rofi' 'gawk')
makedepends=('git')
optdepends=(
  'wl-clipboard: Wayland clipboard support'
  'xclip: X11 clipboard support'
  'xsel: X11 clipboard support (alternative)'
  'kdialog: optional Copied popup'
)
# Local clone name must not collide with the `snippet-picker` script in $startdir.
source=("snippet-picker-src::git+file://${startdir}#tag=v${pkgver}")
sha256sums=('SKIP')

package() {
  cd "$srcdir/snippet-picker-src"
  local libdir="$pkgdir/usr/lib/$pkgname"

  install -Dm755 snippet-picker "$libdir/snippet-picker"
  install -Dm755 rofi-snippet-mode.sh "$libdir/rofi-snippet-mode.sh"
  install -Dm644 snippet-picker.rasi "$libdir/snippet-picker.rasi"
  install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"

  # Wrapper so SCRIPT_DIR resolves to /usr/lib/snippet-picker (not /usr/bin).
  install -d "$pkgdir/usr/bin"
  cat > "$pkgdir/usr/bin/$pkgname" <<EOF
#!/bin/bash
exec /usr/lib/$pkgname/snippet-picker "\$@"
EOF
  chmod 755 "$pkgdir/usr/bin/$pkgname"
}
