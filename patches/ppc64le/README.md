# Chromium PPC64LE patches

Downstream patches to build Chromium on Linux PPC64LE (POWER8+). Sourced from
the Fedora `chromium.spec` `%ifarch ppc64le` block. Patches were authored
against Chromium 144.x–147.x; the tree they are applied to here is 149.x, so
some hunks need rebasing.

## Layout

- `series` — full ordered list of every PPC64 patch (matches spec order).
- `applied-on-macos.txt` — the 21 patches that applied cleanly against 149.x
  `src` only; each is already committed on the `ppc64le` branch.
- `deferred-needs-gclient-sync.txt` — the 17 patches that failed because they
  target `third_party/` deps populated by `gclient sync`, or have drifted.
- `apply.sh` — helper to run `patch -p1 --fuzz=2` against a list.

## Build host workflow (Fedora 44 PPC64LE)

1. Check out this branch, run `gclient sync`.
2. `patches/ppc64le/apply.sh` to apply the deferred set.
3. Address any remaining rebase needs (Category B in the deferred file).
4. Proceed with `gn gen out/Release` and `autoninja`.
