# PLAN — Chromium PPC64LE port, session handoff

**Goal:** build Chromium 149.0.7805.0 on Fedora 44 PPC64LE (POWER8+, target host `tle@192.168.1.247`).
**Branch:** `ppc64le` (29 commits above `main`, HEAD `f58b35e0f5`).
**Source:** git — `runlevel5/chromium` fork (shallow clone on macOS prep box). Not using `gclient` / `depot_tools` because the PPC64 arch has no CIPD packages; canonical distro path.

> **Do NOT fetch via `depot_tools` / `gclient sync`.** Trung already vetted this — no PPC64 CIPD. Distro flow uses either the source tarball (`chromium-{version}.tar.xz`) on the build host, or `git submodule update --init --depth=1` on the subset of submodules the patches touch.

---

## 1. State of play (end of last session)

### Patch set (imported from Fedora `~/Work/chromium-patch` spec's `%ifarch ppc64le` block)

38 PPC64 patches total. All accounted for in `patches/ppc64le/`:

| Bucket | Count | Where they live |
|---|---|---|
| Applied on `ppc64le` as in-tree commits (src files only, not submodules) | 21 | See `git log ppc64le ^main` |
| Rebased & committed on `ppc64le` | 3 | libvpx configs `d1496f64ee`, fix-different-data-layouts `f6d198f362`, skia-vsx rename `0901f1fc22` |
| Patch files — dry-run clean against 149.x submodule content | 13 | `patches/ppc64le/*.patch`; applied at build time |
| Tool-generated, regenerate on build host | 1 | `0002-regenerate-xnn-buildgn.patch` (needs Bazel 8+) |

**Every patch is verified to apply cleanly on Chromium 149.0.7805.0**, either as tree commits or via dry-run against shallow submodules. No drift remaining.

### Key rebases during this session

- **skia** (`skia-vsx-instructions.patch`): upstream renamed `SK_CPU_SSE_LEVEL*` → `SK_CPU_X64_LEVEL*` and `SK_CPU_X64_LEVEL_SKX` / `SKRP_CPU_SKX` → `*_ML4`. Mechanical find/replace through the patch fixed all 45 hunks.
- **libvpx configs** (`0002-Remove-bad-ppc64-config` + `0003-Add-ppc64-generated-config`): spec's delete-then-recreate dance corrupted the tree on 149.x. Collapsed into one replacement commit that reaches the same end state (5040 lines, exactly what `0003` intended).
- **fix-different-data-layouts**: upstream refactored `fatal_linker_warnings` into nested apple/non-apple branches; added `current_cpu != "ppc64"` to the correct inner branch.
- **boringssl**: patch content fine; just needed `third_party/perfetto` submodule populated too (patch touches one perfetto file).

### Spec oddity

`Patch398: 0001-Implement-support-for-PPC64-on-Linux.patch` references a file that doesn't exist (only the lowercase `0001-Implement-support-for-ppc64-on-Linux.patch` is present). Treat as a spec typo; ignore.

---

## 2. Submodules populated on this macOS box

Done via `git submodule update --init --depth=1` (no `gclient`):

```
third_party/angle                      2d7868c43e  (~150 MB)
third_party/boringssl/src              81fa30a30f  (~60 MB)
third_party/breakpad/breakpad          8be0e31146  (~50 MB)
third_party/dawn                       5aeba7ad06  (~200 MB)
third_party/libvpx/source/libvpx       b1f431c1eb  (~100 MB)
third_party/lss                        29164a80da  (<5 MB)
third_party/perfetto                   bdf3f42357  (needed by boringssl patch)
third_party/skia                       c52c45b7ac  (~200 MB)
third_party/swiftshader                89556131bf  (~300 MB)
third_party/webrtc                     b4dfb91f96  (~500 MB)
v8                                     79af6bf0ba  (~500 MB)
```

These are the only submodules the PPC64 patches touch. They aren't tracked in the parent repo's index (submodule pointer unchanged). Build-host will need its own `gclient`-free submodule init.

---

## 3. Next actions — on the Fedora host `tle@192.168.1.247`

**Do not** set up depot_tools. Two viable ways to get a full source tree:

### Option A — source tarball (simplest, matches `chromium.spec`)

```bash
# 149.0.7805.0 is a main-branch snapshot (PATCH=0). Tarballs on
# commondatastorage.googleapis.com/chromium-browser-official/ only exist
# for released versions. Pick the closest released tag — likely
# 149.0.7805.<latest released patchlevel>. Confirm from:
#   https://chromiumdash.appspot.com/releases?platform=Linux
curl -O https://commondatastorage.googleapis.com/chromium-browser-official/chromium-149.0.7805.???.tar.xz
# Extract (~30 GB), cd src, skip to §4.
```

### Option B — git + selective submodule init (what we did here)

```bash
cd ~/Work
git clone --depth=1 git@github.com:runlevel5/chromium.git src
cd src
git fetch --depth=1 origin ppc64le
git checkout ppc64le
git submodule update --init --depth=1 --jobs=6 \
  third_party/angle third_party/boringssl/src third_party/breakpad/breakpad \
  third_party/dawn third_party/libvpx/source/libvpx third_party/lss \
  third_party/perfetto third_party/skia third_party/swiftshader \
  third_party/webrtc v8
# Need additional submodules for build — expect to add as ninja complains.
```

**Note:** Option B will miss many submodules the actual build needs (icu, protobuf, abseil, ffmpeg, etc. — Chromium has ~400+ submodules). Option A is likely less painful. If you pick B, expect to keep expanding the submodule-init list as the build demands.

---

## 4. Apply the submodule-touching patches

```bash
cd ~/Work/chromium    # or wherever the 149.x tree is
patches/ppc64le/apply.sh   # runs patch -p1 --fuzz=2 over deferred-needs-gclient-sync.txt
```

Expect all 13 to apply clean (already verified via dry-run).

### Regenerate xnnpack BUILD.gn

```bash
cd third_party/xnnpack
python3 generate_build_gn.py      # requires Bazel 8+ on PATH
# (the 0001-add-xnn-ppc64el-support.patch has already been committed in-tree
#  on the ppc64le branch, so this run will produce ppc64-aware output)
```

---

## 5. First build attempt

```bash
gn gen out/Release --args='
  target_cpu="ppc64"
  is_debug=false
  is_component_build=true
  is_clang=true
  use_remoteexec=false
  use_sysroot=false
  use_custom_libcxx=false
  enable_nacl=false
  treat_warnings_as_errors=false
  proprietary_codecs=false
  ffmpeg_branding="Chromium"
  symbol_level=1
'
autoninja -C out/Release chrome 2>&1 | tee /tmp/build-01.log
```

### Pre-flight verifications before the first build

1. **V8 PPC64 backend sanity check**: `ls v8/src/codegen/ppc/` and `ls v8/src/maglev/ppc/` — should contain codegen + macro-assembler + (for Maglev) mid-tier JIT code. Confirmed present on 149.x V8 (submodule pin `79af6bf0ba`, V8 14.9.154). PPC64 is an **externally-maintained port** in V8 (not the officially-supported x64/arm64 tier), owned by an IBM + Red Hat team (`PPC_OWNERS`). Google CI doesn't block V8 releases on PPC regressions, so a new release can occasionally ship with PPC temporarily broken until the port team catches up — survivable, just means an occasional follow-up patch. V8 has a ppc64 simulator CI builder (`V8 Linux - ppc64 - sim` in `v8/infra/testing/builders.pyl`).
2. **Toolchain versions**:
   - `clang --version` — need 16+ (17+ preferred for data-layout compatibility with rustc 1.73+).
   - `rustc --version` — 1.73+.
   - `gn --version`; `ninja --version` (system packages, not Google's CIPD).
   - `python3 --version` (3.9+ for build scripts).
3. **Bazel 8+** installed if you plan to regenerate xnnpack's BUILD.gn.

---

## 6. Known risks / things to watch during build

- **V8 port breakage windows.** PPC64 is an externally-maintained V8 port (IBM/RH own it; see 5.1). When upstream V8 lands a new feature, there's a days-to-weeks window where PPC may not yet compile clean until the port team catches up. If the build breaks inside `v8/` after a Chromium roll, check `v8/OWNERS` and `PPC_OWNERS` for whoever is currently tracking ppc, look for a port commit on chromium-review.googlesource.com, cherry-pick it onto our branch.
- **`[[clang::musttail]]` disabled in 3 places** via HACK patches — fragments stacks on ppc64. With a new enough clang, try removing the HACK patches and see if musttail now works on ppc64 targets.
- **Cross-compilation limitations**. Protobuf / mojo bindings / V8 snapshot typically build a native host binary first. If cross-building from x86, these break; fine when building natively on ppc64le.
- **Rust `unknown target`** — `fix-rustc.patch` sets `rust_abi_target = "powerpc64le-unknown-linux-gnu"`. Verify rustc actually has that target installed: `rustc --print target-list | grep ppc64`.
- **Link failures mentioning `--whole-archive`** — `fix-rust-linking.patch` should be live; wraps shared-lib links in `--start-group`/`--end-group`.
- **`sandbox/linux/system_headers/ppc64_linux_syscalls.h` syscall numbers** — if the build host kernel has new syscalls the seccomp BPF whitelist doesn't know about, may see EPERM at runtime (not build failure).
- **64 KiB page kernel assumptions** — some Chromium code still hardcodes 4 KiB. `fix-page-allocator-overflow.patch` + `add-ppc64-pthread-stack-size.patch` cover the known cases. Watch for runtime crashes in shmem/mmap paths.

---

## 7. Assessment of what's covered vs. what's missing

See `patches/ppc64le/STATUS_AND_PLAN.md` for the fuller breakdown. Brief summary:

**Covered by the patch series (builds):** arch macros, GN toolchain, PartitionAlloc 64-bit + 64K page, sandbox seccomp-bpf, BoringSSL (AES-P8, GHASH-P8, ChaCha20/Poly1305 asm), libvpx configs (forced generic-gnu), libaom pregenerated, Skia VSX opts, Breakpad ppc64 minidump + VMX registers, Crashpad curl transport, V8 tuning (POWER8 baseline, pointer compression, trap asm), WebRTC, Dawn detection, Rust toolchain + linking workaround, pthread stack, pffft altivec.

**Known gaps / runtime limitations:**

- **Widevine CDM** — no ppc64le binary exists. DRM-gated content breaks.
- **VA-API / V4L2 hardware video** — spec disables; software only.
- **WebGPU/Dawn backends** — only platform detection patched; no GPU backend validated on ppc64.
- **XNNPACK vector kernels** — ppc64 falls through to scalar; ML inference slow.
- **Upstream CI** — none; every rebase is a manual port.

---

## 8. Quick reference

| Thing | Path |
|---|---|
| Patch files | `patches/ppc64le/*.patch` |
| Series order | `patches/ppc64le/series` |
| Deferred list (apply at build time) | `patches/ppc64le/deferred-needs-gclient-sync.txt` |
| Apply script | `patches/ppc64le/apply.sh` |
| Full coverage/plan doc | `patches/ppc64le/STATUS_AND_PLAN.md` |
| This file (session handoff) | `PLAN.md` |
| Source of original patches | `~/Work/chromium-patch/` (Fedora spec repo, separate from this tree) |
| Remote build host | `tle@192.168.1.247` (Fedora 44 PPC64LE) |
| Branch | `ppc64le` (HEAD `f58b35e0f5`) |
| Upstream base | `main` @ `12416d2603` (Chromium 149.0.7805.0) |
| Fork | `git@github.com:runlevel5/chromium.git` |

### Next-session resume checklist

1. `git log ppc64le ^main | head -30` — confirm branch state is intact.
2. `cat PLAN.md` (this file) — re-orient.
3. Decide: stay in rebase mode here, or move to build iteration on `tle@192.168.1.247`?
4. If moving to build host: follow §3–§5 above. Expect the first `autoninja` run to fail on one of: (a) missing submodule, (b) V8-ppc64 absence, (c) a hunk not listed here that bit-rotted between session end and build host checkout.
