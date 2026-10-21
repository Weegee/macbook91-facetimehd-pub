# SPDX-License-Identifier: GPL-2.0-or-later
# Out-of-tree build of the facetimehd driver as macbook91-facetimehd.
# Replaces upstream's Makefile in the assembled tree (packaging/overlay/); the
# module's objects are listed in Kbuild next to it.

KVERSION ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVERSION)/build
KCONFIG := $(KDIR)/.config

# Build with the compiler family the target kernel was built with: CachyOS
# ships clang/ThinLTO kernels (needs LLVM=1) next to GCC-built LTS kernels.
ifeq ($(shell grep -qx 'CONFIG_CC_IS_CLANG=y' $(KCONFIG) 2>/dev/null && echo y),y)
TOOLCHAIN := LLVM=1
else
TOOLCHAIN :=
endif

all: check
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(TOOLCHAIN) modules

# Fail closed: no build from a modified tree, against an incomplete kernel
# tree or with a missing compiler. SOURCES.sha256 is written by
# packaging/fetch-upstream.sh when it assembles the tree.
check:
	@cd "$(CURDIR)" && sha256sum --quiet -c SOURCES.sha256 || { echo "ERROR: sources do not match SOURCES.sha256"; exit 1; }
	@test -r "$(KCONFIG)" || { echo "ERROR: no .config in $(KDIR)"; exit 1; }
	@test -r "$(KDIR)/Module.symvers" || { echo "ERROR: no Module.symvers in $(KDIR)"; exit 1; }
	@test -r "$(KDIR)/include/generated/utsrelease.h" || { echo "ERROR: no utsrelease.h in $(KDIR)"; exit 1; }
	@if grep -qx 'CONFIG_CC_IS_CLANG=y' "$(KCONFIG)"; then \
	   for t in clang ld.lld llvm-ar; do command -v $$t >/dev/null || { echo "ERROR: kernel is built with clang but $$t is missing"; exit 1; }; done; \
	 elif grep -qx 'CONFIG_CC_IS_GCC=y' "$(KCONFIG)"; then \
	   command -v gcc >/dev/null || { echo "ERROR: kernel is built with GCC but gcc is missing"; exit 1; }; \
	 else echo "ERROR: $(KCONFIG) declares neither CONFIG_CC_IS_CLANG nor CONFIG_CC_IS_GCC"; exit 1; fi

clean:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(TOOLCHAIN) clean

.PHONY: all check clean
