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

## 3. Source sync to the Fedora host `tle@192.168.1.247`

**Approach:** plain `git` on the Fedora box. **Do not** use `depot_tools` / `gclient` (no PPC64 CIPD packages), and don't bother rsync'ing from the macOS prep box (the `ppc64le` branch is already pushed to GitHub; LAN rsync would save ~2 GB of submodule content out of ~15–20 GB total, not worth the filesystem-case and `.git/modules/` plumbing risk).

Target layout on Fedora: `~/Work/chromium/` (the source root, *not* `~/Work/src/`).

### 3.1 Clone the branch

```bash
# Fresh ssh session on tle@192.168.1.247
mkdir -p ~/Work && cd ~/Work
git clone -b ppc64le git@github.com:runlevel5/chromium.git chromium
cd chromium

# Sanity checks
git log --oneline -5
#  expect HEAD ~ "Correct V8 PPC64 status: ..."
git log --oneline ppc64le ^main | wc -l     # expect 32
ls patches/ppc64le/ | head
```

If you want to avoid cloning the full history, add `--depth=50` to the clone — the `ppc64le` branch is only ~32 commits above `main`, so 50 is plenty and keeps the `.git/` small.

### 3.2 Populate the submodules our PPC64 patches touch (~2 GB)

These 11 are the ones verified against in this session. Shallow (`--depth=1`), parallel fetch.

```bash
git submodule update --init --depth=1 --jobs=6 \
  third_party/angle \
  third_party/boringssl/src \
  third_party/breakpad/breakpad \
  third_party/dawn \
  third_party/libvpx/source/libvpx \
  third_party/lss \
  third_party/perfetto \
  third_party/skia \
  third_party/swiftshader \
  third_party/webrtc \
  v8
```

Check each landed at the expected pin (should match the pins listed in §2).

### 3.3 Populate the remaining submodules needed for a full build

Chromium has ~400 submodules. The 11 above only cover what our PPC64 patches modify; the build also wants `third_party/icu`, `abseil-cpp`, `protobuf`, `ffmpeg`, `harfbuzz`, `freetype`, `zlib`, `xnnpack` source, plus everything nested inside `v8/` / `skia/` / `angle/` for their own deps.

**First — skip Googler-only submodules**, or `git submodule update` will prompt for credentials on `chrome-internal.googlesource.com`. gclient tags these via `gclient-condition = checkout_src_internal`, but plain git doesn't honor that, so we mark them `update = none` in local config. The chrome-internal URLs appear at **multiple nesting levels** — top-level Chromium has 81 of them, and several submodules (angle, v8, etc.) reference more in their own `.gitmodules`. So we apply the skip in a loop.

```bash
# Inside ~/Work/chromium

# 1. Disable interactive prompts — any chrome-internal that slips through
#    the skip filter will fail in ~1 second instead of blocking.
export GIT_TERMINAL_PROMPT=0

# 2. Define the skip helper (shell function used twice below).
define_skip() {
  cat <<'EOF'
if [ -f .gitmodules ]; then
  git config --file .gitmodules --name-only --get-regexp "\.url\$" | \
    while read key; do
      url=$(git config --file .gitmodules --get "$key")
      case "$url" in
        https://chrome-internal.googlesource.com/*)
          name="${key#submodule.}"; name="${name%.url}"
          git config "submodule.${name}.update" none
          ;;
      esac
    done
fi
EOF
}

# 3. Apply at top level
eval "$(define_skip)"

# 4. Pull first layer (top-level submodules) non-recursively.
#    ~2 GB, a few minutes.
git submodule update --init --depth=1 --jobs=8

# 5. Apply the same skip inside every newly-initialized submodule
#    (angle, v8, etc. — each has its own .gitmodules with more chrome-internal refs).
git submodule foreach --recursive "$(define_skip)"

# 6. Now pull the rest recursively. 10–20 GB, 30–90 minutes.
git submodule update --init --recursive --depth=1 --jobs=8

# 7. If you see another chrome-internal credential prompt surface during step 6,
#    it means a deeper nesting level showed up that step 5 couldn't preempt
#    (the submodule hadn't been cloned yet). Ctrl-C, re-run steps 5 and 6.
#    Chromium's submodule tree is at most 3–4 levels deep, so 2–3 iterations
#    cover everything.
```

**Sanity check:**
```bash
git config --get-regexp '^submodule\..*\.update' | grep -c ' none$'   # ≥ 81 at top level
```

(Optional — also skip platform-gated submodules you don't need for a Linux-PPC64 build: android / ios / chromeos / fuchsia / mac. Same `update = none` pattern but matching `.gclient-condition` keys with conditions that don't include `checkout_linux`; saves another few GB of download.)

If `git submodule update` dies mid-way, rerun — it's resumable. Occasionally a submodule's default branch doesn't contain the pinned SHA as a reachable ref on a shallow fetch; when that happens git falls back to a direct SHA fetch (`trying to directly fetch <sha>` in stderr), which has worked on every submodule we've tried.

**Expected failure: HTTP 429 / `Short term server-time rate limit exceeded` from googlesource.com.** Their per-IP rate limiter trips when `--jobs=8 --recursive` fires too many concurrent fetches. The error is polite ("please slow down"), not fatal. Wait 5–10 minutes for the short-term window to clear, then retry with lower concurrency:

```bash
git submodule update --init --recursive --depth=1 --jobs=2   # or --jobs=1
```

Submodule update is idempotent — already-initialized submodules are skipped on retry, half-fetched ones get completed. Sequential `--jobs=1` is guaranteed not to rate-limit.

Post-sync sanity checks:
```bash
du -sh .git third_party v8            # ~ few hundred MB .git, ~10–15 GB third_party + v8
ls v8/src/codegen/ppc/                 # non-empty
ls v8/src/maglev/ppc/                  # non-empty
ls third_party/skia/src/opts/          # non-empty
git submodule status --recursive | grep -c '^[-+U]' || echo all-clean
```

### 3.4 Apply the build-time patches to submodule content

The 21 "in-tree" patches are already committed on the branch; only the 14 submodule-targeting patches still need to run (plus the xnn-regenerate step, which is tool-output rather than a patch).

```bash
patches/ppc64le/apply.sh
# internally: patch -p1 --fuzz=2 over the entries in
# patches/ppc64le/deferred-needs-gclient-sync.txt
```

Expect all 14 to apply cleanly — every one was dry-run-verified on macOS against the exact submodule pins the branch references.

### 3.5 Regenerate `third_party/xnnpack/BUILD.gn`

This patch (`0002-regenerate-xnn-buildgn.patch`) is tool output, not hand-written. Run the generator instead of applying the patch.

```bash
cd third_party/xnnpack
python3 generate_build_gn.py           # needs Bazel 8+ on PATH
cd ../..
git -C third_party/xnnpack add BUILD.gn
git -C third_party/xnnpack -c user.email=... -c user.name=... \
    commit -m "ppc64le: regenerate BUILD.gn"
```

If Bazel isn't installed: `dnf install bazel` (Fedora 44 ships Bazel 7+; confirm it's 8+ with `bazel --version`). If unavailable, skip this step and expect xnnpack to build with stock upstream BUILD.gn — you'll lose ppc64-aware source-list generation but the build may still succeed in a reduced form.

### 3.6 Keeping in sync across macOS ↔ Fedora going forward

No rsync needed for iteration:

- **When you rebase a patch on macOS:** commit on `ppc64le` branch, `git push`, then on Fedora `git pull`. If a patch now touches a submodule differently, `git submodule update --recursive` after pulling.
- **When you fix something on Fedora:** commit on `ppc64le`, `git push`, pull back to macOS. Keep per-submodule fixes out of the parent branch (commit them in the submodule's own tree if you need to, but our current design keeps all fixes in patch files under `patches/ppc64le/` so they stay reviewable and travel with the main repo).

---

## 4. First build attempt

```bash
# Still in ~/Work/chromium on the Fedora host.
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

### 4.1 Pre-flight verifications before the first build

1. **V8 PPC64 backend sanity check**: `ls v8/src/codegen/ppc/` and `ls v8/src/maglev/ppc/` — should contain codegen + macro-assembler + (for Maglev) mid-tier JIT code. Confirmed present on 149.x V8 (submodule pin `79af6bf0ba`, V8 14.9.154). PPC64 is an **externally-maintained port** in V8 (not the officially-supported x64/arm64 tier), owned by an IBM + Red Hat team (`PPC_OWNERS`). Google CI doesn't block V8 releases on PPC regressions, so a new release can occasionally ship with PPC temporarily broken until the port team catches up — survivable, just means an occasional follow-up patch. V8 has a ppc64 simulator CI builder (`V8 Linux - ppc64 - sim` in `v8/infra/testing/builders.pyl`).
2. **Toolchain versions**:
   - `clang --version` — need 16+ (17+ preferred for data-layout compatibility with rustc 1.73+).
   - `rustc --version` — 1.73+.
   - `gn --version`; `ninja --version` (system packages, not Google's CIPD).
   - `python3 --version` (3.9+ for build scripts).
3. **Bazel 8+** installed if you plan to regenerate xnnpack's BUILD.gn.

---

## 5. Known risks / things to watch during build

- **V8 port breakage windows.** PPC64 is an externally-maintained V8 port (IBM/RH own it; see §4.1). When upstream V8 lands a new feature, there's a days-to-weeks window where PPC may not yet compile clean until the port team catches up. If the build breaks inside `v8/` after a Chromium roll, check `v8/OWNERS` and `PPC_OWNERS` for whoever is currently tracking ppc, look for a port commit on chromium-review.googlesource.com, cherry-pick it onto our branch.
- **`[[clang::musttail]]` disabled in 3 places** via HACK patches — fragments stacks on ppc64. With a new enough clang, try removing the HACK patches and see if musttail now works on ppc64 targets.
- **Cross-compilation limitations**. Protobuf / mojo bindings / V8 snapshot typically build a native host binary first. If cross-building from x86, these break; fine when building natively on ppc64le.
- **Rust `unknown target`** — `fix-rustc.patch` sets `rust_abi_target = "powerpc64le-unknown-linux-gnu"`. Verify rustc actually has that target installed: `rustc --print target-list | grep ppc64`.
- **Link failures mentioning `--whole-archive`** — `fix-rust-linking.patch` should be live; wraps shared-lib links in `--start-group`/`--end-group`.
- **`sandbox/linux/system_headers/ppc64_linux_syscalls.h` syscall numbers** — if the build host kernel has new syscalls the seccomp BPF whitelist doesn't know about, may see EPERM at runtime (not build failure).
- **64 KiB page kernel assumptions** — some Chromium code still hardcodes 4 KiB. `fix-page-allocator-overflow.patch` + `add-ppc64-pthread-stack-size.patch` cover the known cases. Watch for runtime crashes in shmem/mmap paths.

---

## 6. Assessment of what's covered vs. what's missing

See `patches/ppc64le/STATUS_AND_PLAN.md` for the fuller breakdown. Brief summary:

**Covered by the patch series (builds):** arch macros, GN toolchain, PartitionAlloc 64-bit + 64K page, sandbox seccomp-bpf, BoringSSL (AES-P8, GHASH-P8, ChaCha20/Poly1305 asm), libvpx configs (forced generic-gnu), libaom pregenerated, Skia VSX opts, Breakpad ppc64 minidump + VMX registers, Crashpad curl transport, V8 tuning (POWER8 baseline, pointer compression, trap asm), WebRTC, Dawn detection, Rust toolchain + linking workaround, pthread stack, pffft altivec.

**Known gaps / runtime limitations:**

- **Widevine CDM** — no ppc64le binary exists. DRM-gated content breaks.
- **VA-API / V4L2 hardware video** — spec disables; software only.
- **WebGPU/Dawn backends** — only platform detection patched; no GPU backend validated on ppc64.
- **XNNPACK vector kernels** — ppc64 falls through to scalar; ML inference slow.
- **Upstream CI** — none; every rebase is a manual port.

---

## 7. Quick reference

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
4. If moving to build host: follow §3 (clone + submodules + patches) and §4 (build). Expect the first `autoninja` run to fail on one of: (a) a submodule the build wants that `--recursive` didn't pick up (rare but possible), (b) a hunk not listed here that bit-rotted between session end and build host checkout, (c) a clang/rustc version mismatch that `fix-different-data-layouts.patch` doesn't cover.
