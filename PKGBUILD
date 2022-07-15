# Maintainer: harttle <yangjvn@126.com>
# Inspired by lighter, many thanks to Janhouse's perl script https://github.com/Janhouse/lighter
pkgname=macbook-lighter
pkgver=v0.0.2.6
pkgrel=1
pkgdesc="Macbook pro 2019 screen/keyboard backlight CLI and auto-adjust on ambient light"
arch=(any)
url="https://github.com/x-finity/macbook-lighter"
license=('GPL')
depends=('bc')
makedepends=('git')
provides=()
conflicts=()
source=('git+https://github.com/x-finity/macbook-lighter.git')
md5sums=('SKIP')

pkgver() {
  cd "$srcdir/$pkgname"
  git describe --tags | sed 's|-|.|g'
}

package() {
  cd "$srcdir/$pkgname"
  [ ! -f $pkgdir/etc/autolight.conf ] && install -Dm644 autolight.conf $pkgdir/etc/autolight.conf
  install -Dm644 "macbook-lighter.service" "$pkgdir/usr/lib/systemd/system/macbook-lighter.service"
  install -Dm755 "src/macbook-lighter-ambient.sh" "$pkgdir/usr/bin/macbook-lighter-ambient"
  install -Dm755 "src/macbook-lighter-screen.sh" "$pkgdir/usr/bin/macbook-lighter-screen"
  install -Dm755 "src/macbook-lighter-kbd.sh" "$pkgdir/usr/bin/macbook-lighter-kbd"
}
