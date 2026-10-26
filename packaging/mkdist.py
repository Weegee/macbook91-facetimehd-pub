#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the package's source tarball, byte-reproducibly.

Output: dist/NAME-VERSION.tar and .sha256 (or --out DIR). The tarball is what
packaging/arch/PKGBUILD pins, so it has to be the same bytes every time it is
built from the same inputs.

Contents, under NAME-VERSION/, laid out as in the repository so the Makefile's
`install` target works in both places:

  src/macbook91-facetimehd/   the DKMS tree packaging/fetch-upstream.sh
                              assembled from the upstream commit and patches
                              in packaging/upstream.lock. None of it is
                              tracked here; exactly the files SOURCES.sha256
                              lists are taken, each checked against it, plus
                              SOURCES.sha256 and dkms.conf
  tools/macbook91-facetimehd-verify, tools/macbook91-facetimehd-fetch-firmware,
  tools/macbook91-facetimehd-kernel-series, tools/macbook91-facetimehd-series.hook,
  Makefile, VERSION, LICENSE,
  LICENSES/GPL-2.0-only.txt, LICENSES/GPL-2.0-or-later.txt, README.md

Any other file in the module tree that is not a build artifact is refused: an
unknown file must never reach /usr/src unseen. So is - unless --allow-dirty - a
tracked file with uncommitted changes, because a release tarball holds
committed content only.

Entries are sorted, owned by 0:0, mode 0755 for executables and 0644
otherwise, all with mtime 0. The tar is not compressed: gzip output depends on
the zlib implementation, and the pinned checksum has to hold on every machine.
Same scheme as packaging/mkdist.py in macbook91-cs4208.
"""

from __future__ import annotations

import fnmatch
import hashlib
import io
import os
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "macbook91-facetimehd"
MODULE = "src/macbook91-facetimehd"
# Written by fetch-upstream.sh next to the files SOURCES.sha256 lists.
META = ("SOURCES.sha256", "dkms.conf")
# Build output a module build leaves behind; never packaged, never an error.
ARTIFACTS = ("*.o", "*.ko", "*.mod", "*.mod.c", "*.symvers", "*.order", ".*.cmd", ".tmp_versions/*")
EXTRA = (
    "tools/macbook91-facetimehd-verify",
    "tools/macbook91-facetimehd-fetch-firmware",
    "tools/macbook91-facetimehd-kernel-series",
    "tools/macbook91-facetimehd-series.hook",
    "Makefile",
    "VERSION",
    "LICENSE",
    "LICENSES/GPL-2.0-only.txt",
    "LICENSES/GPL-2.0-or-later.txt",
    "README.md",
)


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True).stdout


def fail(msg: str) -> int:
    print(f"mkdist: {msg}", file=sys.stderr)
    return 1


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main(argv: list[str]) -> int:
    allow_dirty = "--allow-dirty" in argv
    out_dir = os.path.join(ROOT, "dist")
    if "--out" in argv:
        out_dir = os.path.abspath(argv[argv.index("--out") + 1])
    with open(os.path.join(ROOT, "VERSION"), encoding="ascii") as fh:
        version = fh.read().strip()

    if not allow_dirty and git("status", "--porcelain", "--untracked-files=no").strip():
        return fail("working tree has uncommitted changes; commit first (or --allow-dirty)")

    tracked = set(f for f in git("ls-files", "-z", "--", *EXTRA).split("\0") if f)
    for f in EXTRA:
        if f not in tracked:
            return fail(f"{f} is not tracked")

    mod = os.path.join(ROOT, MODULE)
    sums = os.path.join(mod, "SOURCES.sha256")
    if not os.path.isfile(sums):
        return fail(f"{MODULE} is not assembled; run packaging/fetch-upstream.sh")
    listed = {}
    with open(sums, encoding="utf-8") as fh:
        for line in fh:
            digest, rel = line.rstrip("\n").split("  ", 1)
            listed[rel] = digest
    for rel, digest in sorted(listed.items()):
        path = os.path.join(mod, rel)
        if not os.path.isfile(path) or sha256(path) != digest:
            return fail(f"{MODULE}/{rel} is missing or does not match SOURCES.sha256")
    for m in META:
        if not os.path.isfile(os.path.join(mod, m)):
            return fail(f"{MODULE}/{m} is missing")

    unknown = []
    for dirpath, _dirs, names in os.walk(mod):
        for n in names:
            rel = os.path.relpath(os.path.join(dirpath, n), mod)
            if rel in listed or rel in META:
                continue
            if any(fnmatch.fnmatch(n, p) or fnmatch.fnmatch(rel, p) for p in ARTIFACTS):
                continue
            unknown.append(rel)
    if unknown:
        return fail(f"unexpected files in the module tree: {', '.join(sorted(unknown))}")

    files = sorted({f"{MODULE}/{r}" for r in (*listed, *META)} | set(EXTRA))

    prefix = f"{NAME}-{version}"
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        parents = {os.path.dirname(f) for f in files} - {""}
        all_dirs = sorted({"/".join(d.split("/")[: i + 1]) for d in parents for i in range(d.count("/") + 1)})
        for d in ["", *all_dirs]:
            info = tarfile.TarInfo(f"{prefix}/{d}".rstrip("/"))
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = 0
            tar.addfile(info)
        for f in files:
            path = os.path.join(ROOT, f)
            with open(path, "rb") as fh:
                data = fh.read()
            info = tarfile.TarInfo(f"{prefix}/{f}")
            info.size = len(data)
            info.mode = 0o755 if os.stat(path).st_mode & 0o111 else 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, f"{prefix}.tar")
    with open(target, "wb") as fh:
        fh.write(raw.getvalue())
    digest = sha256(target)
    with open(target + ".sha256", "w", encoding="ascii") as fh:
        fh.write(f"{digest}  {prefix}.tar\n")
    print(f"{digest}  {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
