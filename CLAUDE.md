# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rich existing guidance

Before acting, consult the Chromium-maintained agent guidance (written for gemini-cli, but the rules apply to any AI agent):

- `agents/prompts/common.md` — standard edit/fix workflow (read-before-write, mandatory build+test after edits, how to approach compile errors).
- `agents/prompts/knowledge_base.md` — task-oriented pointers to the right docs for IPC, threading, prefs, UMA/UKM, Blink, BUILD.gn debugging.
- `agents/ai_policy.md` — binding policy. Authors must fully understand any code submitted; unreviewed AI-authored CLs can cost committer status. Flag AI-assisted areas the author is unsure about.
- `docs/README.md` rooted tree and `docs/imported/` — canonical in-tree documentation; prefer these over general knowledge.
- `styleguide/styleguide.md` — links to every language-specific style guide (C++, Blink C++, Java, Rust, Python, GN, etc.). Blink has its own C++ rules distinct from the rest of Chromium.

## Build, test, presubmit

Commands assume an already-configured output directory (commonly `out/Default`). If no `OUT_DIR` has been established, stop and ask before building — Chromium builds are long and configuration-sensitive.

- Configure once per output dir: `gn gen out/Default` (edit `out/Default/args.gn` for `is_debug`, `is_component_build`, `symbol_level`, `use_remoteexec`, etc.).
- Build: `autoninja --quiet -C out/Default <target>` — always pass `--quiet`.
- Run a single test file (builds needed targets automatically — do NOT run `autoninja` first):
  `tools/autotest.py --quiet --run-all -C out/Default path/to/foo_unittest.cc`
  Targets containing `:` aren't valid inputs; pass filenames.
- Filter within a built test binary: `out/Default/unit_tests --gtest_filter="SomeTest.*"`.
- Find the test target for a file: `gn refs out/Default --testonly=true --type=executable --all path/to/foo_unittest.cc`.
- Before upload: `git cl format` then `git cl presubmit -u --force`. Fix only warnings/errors on lines you touched; leave pre-existing warnings alone.
- CLs go to Gerrit via `git cl upload` (not GitHub PRs). Commit descriptions use `Bug: 123456` footer syntax; see `docs/contributing.md`.

## Architecture big picture

Chromium is a multi-process browser. Understanding the layering is prerequisite to making changes without layering violations.

- **Processes**: browser (privileged, UI), renderer (sandboxed, one per site-instance), GPU, utility, network. Cross-process calls go through **Mojo** interfaces defined in `.mojom` files. When a task involves communication between components/processes, find the `.mojom` first — it defines the contract. See `docs/mojo_and_services.md`.
- **Layering** (lower cannot depend on higher; enforced by `DEPS`):
  - `base/` — foundational primitives (tasks, callbacks, strings, containers).
  - `//content` — core web-platform implementation (multi-process plumbing, navigation, rendering, GPU accel). Contains only features that are web-platform (tracked on chromestatus, have a spec). Embedders hook in via `ContentClient` / `ContentBrowserClient` / `ContentRendererClient`. See `content/README.md`.
  - `//chrome` — browser-product features (extensions, autofill, sync, safe browsing, translate, spellcheck). Depends on `//content`, never the reverse.
  - `//components/*` — reusable feature modules shared across embedders (chrome, android_webview, ios, ash).
  - Other top-level product dirs: `android_webview/`, `ash/` (ChromeOS shell), `ios/`, `chromecast/`, `fuchsia_web/`, `headless/`.
- **Blink** lives at `third_party/blink/renderer/`. It is a boundary: use `blink::Vector` / `blink::String` from `third_party/blink/renderer/platform/wtf/` and Oilpan GC types (`Member<>`, `WeakMember<>`, `Persistent<>`) — NOT STL or most `base/` equivalents. Follow `styleguide/c++/blink-c++.md`.
- **Threading**: task posting via `base::TaskRunner` + `base::BindOnce`/`BindRepeating`. UI thread vs IO thread distinction matters. See `docs/threading_and_tasks.md` and `docs/callback.md`.
- **Android/JNI** (`//third_party/jni_zero` codegen): Java `@CalledByNative` methods appear in C++ as `Java_…`; Java `@NativeMethods` interfaces become `JNI_…` in C++. A Java parameter `long nativeFooImpl` maps to a `FooImpl::Method` on the C++ side. When changing JNI, edit both the `.java` and `.cc/.h` sides. See `agents/prompts/common.minimal.md` for the full recipe.

## Task-specific entry points

- Adding a pref → `components/prefs/README.md`.
- Adding a UMA histogram → `docs/metrics/uma/README.md`.
- Adding a UKM metric → `tools/metrics/ukm/README.md`.
- Modifying `BUILD.gn` → `docs/imported/gn/style_guide.md`; for "header not found" errors, check target `deps`, then `gn desc <out> //path:target deps` and `gn check <out> //path:target`.
- General runtime debugging / useful flags → `docs/debugging.md`.
- Skills for focused tasks (feature-flag removal, histograms, JNI type conversion, NullAway, network annotations, WebUI Lit migration, etc.) live under `agents/skills/`.

## Workflow rules that bite

- **Read the full source of files you edit before editing.** Don't infer a function's behavior from its name or from other call sites — read the implementation and at least one call site.
- **Stay on task.** Don't fix unrelated TODOs, code health issues, or pre-existing warnings. Scope creep inflates reviews.
- **Never create a new test file** if one already exists for the component — extend the existing one.
- **Build after every edit**, then run relevant tests. Fix compile errors by reading the related files (interface definitions, etc.), not by speculative patches.
- Comments should explain *why*, not *what*; add sparingly.
