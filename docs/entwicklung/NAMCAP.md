# namcap

`namcap` on the driver package of 20261021.01 (three warnings, no errors), and why they stay.

| Package | Message | Reason |
|---|---|---|
| dkms | `No ELF files and not an "any" package` | The package ships module sources that DKMS builds for x86_64 kernels; `any` would claim it works elsewhere. Same as macbook91-cs4208. |
| dkms | `Dependency bash detected and implicitly satisfied` | bash is part of every Arch base system. |
| dkms | `Dependency included, but may not be needed ('dkms')` | namcap cannot see that the DKMS tree under /usr/src is built by dkms. |

The driver `PKGBUILD` is clean. (The separate firmware package recipe this table once covered was removed in 20261021.01.)
