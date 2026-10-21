# SPDX-License-Identifier: GPL-3.0-or-later
# Package targets (Arch packaging). Run from the repository root; the
# module itself is built by DKMS from src/macbook91-facetimehd/ with the
# Makefile from packaging/overlay/, not here.
#
#   make check           hermetic tests (tests/run-tests.sh)
#   make dist            assemble src/macbook91-facetimehd/ from the upstream
#                        commit and patches recorded in packaging/upstream.lock,
#                        then write the reproducible source tarball
#                        dist/NAME-VERSION.tar
#   make install         what macbook91-facetimehd-dkms installs; its package()
#                        is exactly `make PREFIX=/usr DESTDIR="$pkgdir" install`,
#                        run from that tarball
#   make srcinfo         regenerate packaging/arch/.SRCINFO
#   make arch-pkg        release build: the tarball's SHA256 must be the one
#                        pinned in packaging/arch/PKGBUILD
#   make arch-pkg-dev    build of an unreleased tree: tracked files as they are
#                        on disk, the pin replaced in the build copy only
#
# Packages are built in build/arch and copied to dist/. MAKEPKG_FLAGS passes
# options to makepkg (e.g. --syncdeps in CI).

NAME := macbook91-facetimehd
VERSION := $(shell cat VERSION)
MODULE := src/macbook91-facetimehd

PREFIX ?= /usr
DESTDIR ?=
MAKEPKG_FLAGS ?=

SRCDIR = $(DESTDIR)$(PREFIX)/src/$(NAME)-$(VERSION)

.PHONY: check install dist srcinfo arch-pkg arch-pkg-dev _arch-build

check:
	tests/run-tests.sh

install:
	@test -r "$(MODULE)/SOURCES.sha256" || { echo "install: $(MODULE) is not assembled; run make dist" >&2; exit 1; }
	install -dm755 "$(SRCDIR)"
	cp -a "$(MODULE)/." "$(SRCDIR)/"

	# Build artifacts must never reach the package.
	find "$(SRCDIR)" \( -name '*.o' -o -name '*.ko' -o -name '*.mod*' -o -name '.*.cmd' \) -delete
	rm -f "$(SRCDIR)/Module.symvers" "$(SRCDIR)/modules.order"

	# dkms.conf carries the version from the package, not a hardcoded string.
	sed -i "s/@PKGVER@/$(VERSION)/" "$(SRCDIR)/dkms.conf"

	install -Dm755 tools/macbook91-facetimehd-verify \
		"$(DESTDIR)$(PREFIX)/bin/macbook91-facetimehd-verify"
	install -Dm755 tools/macbook91-facetimehd-fetch-firmware \
		"$(DESTDIR)$(PREFIX)/bin/macbook91-facetimehd-fetch-firmware"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/README.md"

	find "$(SRCDIR)" -type f -exec chmod 644 {} +
	find "$(SRCDIR)" -type d -exec chmod 755 {} +

dist:
	packaging/fetch-upstream.sh
	python3 packaging/mkdist.py

srcinfo:
	cd packaging/arch && makepkg --printsrcinfo > .SRCINFO

# The release build. The tarball holds no PKGBUILD, so pinning its checksum
# there does not change the tarball.
arch-pkg: dist
	@want=$$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" packaging/arch/PKGBUILD); \
	have=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256); \
	if [ "$$want" != "$$have" ]; then \
		echo "arch-pkg: PKGBUILD sha256sums is $$want, tarball is $$have" >&2; \
		echo "arch-pkg: set sha256sums to $$have, make srcinfo, commit (--amend), rerun" >&2; \
		exit 1; \
	fi
	$(MAKE) --no-print-directory _arch-build

arch-pkg-dev:
	packaging/fetch-upstream.sh
	python3 packaging/mkdist.py --allow-dirty
	$(MAKE) --no-print-directory _arch-build PIN=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256)

# makepkg extracts into $$srcdir without clearing it, so build/arch is
# recreated every time and makepkg runs with --cleanbuild.
_arch-build:
	rm -rf build/arch
	mkdir -p build/arch
	cp packaging/arch/PKGBUILD packaging/arch/$(NAME)-dkms.install dist/$(NAME)-$(VERSION).tar build/arch/
	if [ -n "$(PIN)" ]; then \
		sed -i "s/^sha256sums=('[0-9a-f]*')/sha256sums=('$(PIN)')/" build/arch/PKGBUILD; \
	fi
	cd build/arch && makepkg --cleanbuild --force --noconfirm $(MAKEPKG_FLAGS)
	cp build/arch/$(NAME)-*$(VERSION)-*.pkg.tar.zst dist/
