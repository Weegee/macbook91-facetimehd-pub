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

Text interface (house text HIG): the result, "SHA256  PATH", is the only line
on stdout; messages go to stderr as "mkdist.py: error: ..." with indented
follow-up lines. Exit 0 done, 1 error, 2 usage error, 130 and 143 after SIGINT
and SIGTERM.
"""

from __future__ import annotations

import fnmatch
import hashlib
import io
import os
import signal
import subprocess
import sys
import tarfile

PROG = "mkdist.py"
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


HELP = """\
Usage: packaging/mkdist.py [--allow-dirty] [--out DIR]

Builds the package's source tarball, byte-reproducibly, and prints its SHA256
and path. The tarball is what packaging/arch/PKGBUILD pins.

Examples:
  python3 packaging/mkdist.py                 write dist/NAME-VERSION.tar from committed files
  python3 packaging/mkdist.py --allow-dirty   include uncommitted changes (unreleased builds only)

Options:
      --allow-dirty   accept tracked files with uncommitted changes
      --out DIR       write the tarball and its .sha256 to DIR (default dist/)
  -h, --help          this help
  -V, --version       version

Files:
  dist/NAME-VERSION.tar          the tarball
  dist/NAME-VERSION.tar.sha256   its SHA256, in sha256sum format

Exit status:
  0    tarball written
  1    error
  2    usage error
  130  interrupted by SIGINT (143 by SIGTERM)

Docs and bug reports: https://github.com/Weegee/macbook91-facetimehd-pub
"""
USAGE = "Usage: packaging/mkdist.py [--allow-dirty] [--out DIR]"


class Fail(Exception):
    """An expected error: the message, then optional hint lines."""

    def __init__(self, msg: str, *hints: str) -> None:
        super().__init__(msg)
        self.hints = hints


def report(msg: str, *hints: str) -> None:
    print(f"{PROG}: error: {msg}", file=sys.stderr)
    for h in hints:
        print(f"  {h}", file=sys.stderr)


def usage_error(msg: str) -> int:
    report(msg)
    print(f"{USAGE}\nExample: python3 packaging/mkdist.py --allow-dirty\nHelp: python3 packaging/mkdist.py --help", file=sys.stderr)
    return 2


def git(*args: str) -> str:
    try:
        return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        raise Fail("git is not installed", "Install it: sudo pacman -S git") from None
    except subprocess.CalledProcessError as exc:
        raise Fail(f"git {args[0]} failed: {exc.stderr.strip() or 'exit status ' + str(exc.returncode)}") from None


def parse(argv: list[str]) -> tuple[bool, str | None] | int:
    """Return (allow_dirty, out) or an exit status when the call is answered here."""
    allow_dirty, out, i = False, None, 0
    if any(a in ("-h", "--help") for a in argv):
        print(HELP, end="")
        return 0
    if any(a in ("-V", "--version") for a in argv):
        print(f"{PROG} {version_of_tree()}")
        return 0
    while i < len(argv):
        a = argv[i]
        if a == "--allow-dirty":
            allow_dirty = True
        elif a == "--out" or a.startswith("--out="):
            if a == "--out":
                i += 1
                if i >= len(argv):
                    return usage_error("option '--out' needs a directory")
                out = argv[i]
            else:
                out = a.split("=", 1)[1]
            if not out:
                return usage_error("option '--out' needs a directory")
        else:
            return usage_error(f"unknown option '{a}'" if a.startswith("-") else f"unexpected argument '{a}'")
        i += 1
    return allow_dirty, out


def version_of_tree() -> str:
    try:
        with open(os.path.join(ROOT, "VERSION"), encoding="ascii") as fh:
            return fh.read().strip()
    except OSError:
        raise Fail("cannot read VERSION", "Run it from a checkout of the repository.") from None


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main(argv: list[str]) -> int:
    parsed = parse(argv)
    if isinstance(parsed, int):
        return parsed
    allow_dirty, out = parsed
    out_dir = os.path.abspath(out) if out else os.path.join(ROOT, "dist")
    version = version_of_tree()

    if not allow_dirty and git("status", "--porcelain", "--untracked-files=no").strip():
        raise Fail("tracked files have uncommitted changes", "Commit them first, or build an unreleased tarball with --allow-dirty.")

    tracked = set(f for f in git("ls-files", "-z", "--", *EXTRA).split("\0") if f)
    for f in EXTRA:
        if f not in tracked:
            raise Fail(f"{f} is not tracked", f"Track it first: git add {f}")

    mod = os.path.join(ROOT, MODULE)
    sums = os.path.join(mod, "SOURCES.sha256")
    assemble = "Assemble the tree: packaging/fetch-upstream.sh"
    if not os.path.isfile(sums):
        raise Fail(f"{MODULE} is not assembled", assemble)
    listed = {}
    with open(sums, encoding="utf-8") as fh:
        for line in fh:
            digest, rel = line.rstrip("\n").split("  ", 1)
            listed[rel] = digest
    for rel, digest in sorted(listed.items()):
        path = os.path.join(mod, rel)
        if not os.path.isfile(path) or sha256(path) != digest:
            raise Fail(f"{MODULE}/{rel} is missing or does not match SOURCES.sha256", assemble)
    for m in META:
        if not os.path.isfile(os.path.join(mod, m)):
            raise Fail(f"{MODULE}/{m} is missing", assemble)

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
        raise Fail(f"unexpected files in the module tree: {', '.join(sorted(unknown))}",
                   "An unknown file must never reach /usr/src unseen. Remove it, or assemble the tree again: packaging/fetch-upstream.sh")

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


def run(argv: list[str]) -> int:
    def on_term(_signum: int, _frame: object) -> None:
        print(f"\n{PROG}: cancelled", file=sys.stderr)
        sys.exit(143)

    signal.signal(signal.SIGTERM, on_term)
    try:
        return main(argv)
    except Fail as exc:
        report(str(exc), *exc.hints)
        return 1
    except KeyboardInterrupt:
        print(f"\n{PROG}: cancelled", file=sys.stderr)
        return 130
    except OSError as exc:
        report(f"{exc.filename or 'I/O'}: {exc.strerror or exc}")
        return 1


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
