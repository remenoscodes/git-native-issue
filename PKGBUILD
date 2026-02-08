# Maintainer: Emerson Soares <remenoscodes@gmail.com>

pkgname=git-native-issue
pkgver=1.0.2
pkgrel=1
pkgdesc="Distributed issue tracking using Git's native data model"
arch=('any')
url="https://github.com/remenoscodes/git-native-issue"
license=('GPL2')
depends=('git' 'jq')
makedepends=()
optdepends=(
    'github-cli: for GitHub bridge functionality'
)
source=("${pkgname}-${pkgver}.tar.gz::https://github.com/remenoscodes/git-native-issue/releases/download/v${pkgver}/git-native-issue-v${pkgver}.tar.gz")
sha256sums=('e9d4cdf6239a7175a651b8dc89bef1b133500306b5e7fe6cd78025f83082d40d')

package() {
    cd "${srcdir}/git-native-issue-v${pkgver}"

    # Install binaries
    install -d "${pkgdir}/usr/bin"
    install -m755 bin/git-issue* "${pkgdir}/usr/bin/"

    # Install documentation
    install -d "${pkgdir}/usr/share/doc/${pkgname}"
    install -m644 README.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 ISSUE-FORMAT.md "${pkgdir}/usr/share/doc/${pkgname}/"
    install -m644 LICENSE "${pkgdir}/usr/share/doc/${pkgname}/"

    # Install man pages if they exist
    if [ -d doc ]; then
        install -d "${pkgdir}/usr/share/man/man1"
        install -m644 doc/*.1 "${pkgdir}/usr/share/man/man1/" 2>/dev/null || true
    fi
}

check() {
    cd "${srcdir}/git-native-issue-v${pkgver}"

    # Basic sanity checks
    [ -f bin/git-issue ] || return 1
    [ -x bin/git-issue ] || return 1

    # Check version
    ./bin/git-issue version | grep -q "${pkgver}" || return 1
}
