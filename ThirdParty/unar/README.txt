# Patched `lsar` / `unar` (XADMaster 1.10.7)

7ZIP4MAC bundles `lsar` and `unar` from The Unarchiver's command-line tools
(library: [XADMaster](https://github.com/MacPaw/XADMaster)) as a fallback for
damaged multi-part RAR sets. **They are not the stock binaries**: they carry a
small patch. This folder is the corresponding source for that modification.

## What was changed

| Patch | Purpose |
|---|---|
| `password-stdin.patch` | Adds `-password-stdin` to `unar` and `lsar`: the password is read from the first line of standard input. Without it the only way to pass a password is `-p SECRET`, which any user of the Mac can read with `ps`. |
| `build-xcode-libcxx.patch` | Build only: the Xcode project asked for the retired `libstdc++`; it now links `libc++`, as Homebrew's own build does. No code change. |

Everything else is upstream, untouched. The four changed source files
(`unar.m`, `lsar.m`, `CommandLineCommon.m`, `CommandLineCommon.h`) begin with a
notice saying they were modified, by whom and when.

## Upstream sources and versions

| Component | Version | Licence | SHA-256 of the release tarball |
|---|---|---|---|
| [XADMaster](https://github.com/MacPaw/XADMaster) (includes libxad-derived code) | v1.10.7 | LGPL-2.1 | `3d766dc1856d04a8fb6de9942a6220d754d0fa7eae635d5287e7b1cf794c4f45` |
| [universal-detector](https://github.com/MacPaw/universal-detector) (Mozilla universalchardet wrapper) | 1.1 | LGPL-2.1 | `8e8532111d0163628eb828a60d67b53133afad3f710b1967e69d3b8eee28a811` |

## Rebuilding

```sh
ThirdParty/unar/build.sh      # fetches, checks the hashes, patches, builds (arm64)
```

The result is written to `ThirdParty/unar/out/` (git-ignored). To use it, copy
`lsar` and `unar` over `App/Resources/Engine/` and sign them ad-hoc
(`Scripts/build.sh` does this when it builds the app).

## Licence

XADMaster and universal-detector are licensed under the GNU Lesser General Public
License, version 2.1 or later (see `App/Resources/Engine/unar-LICENSE-LGPL-2.1.txt`).
The patches in this folder are released under the same licence. The tools run as
separate programs launched by 7ZIP4MAC; nothing is linked into it.

"The Unarchiver" and MacPaw are names of their owners. This modified build is
not made, supported or endorsed by them; report problems with it to 7ZIP4MAC,
not to MacPaw.
