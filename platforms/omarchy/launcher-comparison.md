# Launcher comparison for our Omarchy/Asahi setup

We reviewed Keystroke v1.5.1 at commit `b7a10ca7fb4e4644244b50d29b7b4d16f9db46ff`, Omarchy Launcher v1.0.3, Vicinae v0.29.1, and Walker v2.17.2. This is a source/documentation comparison with limited local compatibility tests, not a security audit or an end-to-end performance benchmark. We did not install or enable a replacement launcher.

## Recommendation

For our stated needs—apps, web search, files, desktop actions, Everforest, and a lean Omarchy-native interface—Keystroke is a strong first trial. It is not a complete Alfred Powerpack equivalent. If custom keywords, parameterized workflows, snippets and a broad extension ecosystem are central rather than occasional, Vicinae is the stronger independent candidate. Omarchy Launcher remains the more feature-rich within-Omarchy alternative for script commands and Raycast-style extensions.

We should start Keystroke with voice disabled, ordinary lexical search, and optional community extensions off. After accepting the UI and file search, we can enable its Small Smart Match model and measure whether it improves our searches. We should not enable its hold-Super+Space voice binding: Kanata deliberately turns that hold into SpaceFN navigation.

## Feature comparison

| Area                         | Keystroke                                             | Omarchy Launcher                                      | Vicinae                                                | Walker + Elephant                                      |
|------------------------------|-------------------------------------------------------|-------------------------------------------------------|--------------------------------------------------------|--------------------------------------------------------|
| Architecture                 | QML/JS inside the existing Omarchy shell               | QML/JS inside Omarchy; Node sidecar for extensions      | Independent native C++/Qt launcher                      | GTK/Rust frontend with separate Elephant backend        |
| Omarchy integration          | Replaces the menu, including select/input pickers      | Separate palette; includes stock menu entries          | Independent; requires action/theme integration          | Independent; requires action/theme integration          |
| Everforest                   | Inherits Omarchy palette directly                     | Inherits Omarchy palette directly                     | Separate launcher theme/config                         | Separate GTK/CSS theme/config                           |
| Apps, maths, URLs            | Built in; conversions and colours too                 | Built in; conversions and colours too                 | Broad built-ins and extension ecosystem                 | Provider-driven apps, calculator, web and more          |
| Web search                   | Google fallback and assistant handoffs                | User quicklinks with query placeholders                | Script/extension-driven search workflows                | Configurable web-search providers                       |
| File search                  | Names/paths under home, fd-based, no persistent index  | Names and ripgrep content search with actions           | File-search workflows and richer action model           | Elephant file provider                                  |
| File action depth            | Open; alternate opens terminal in parent              | Copy path/file, reveal, editor, terminal, trash         | Broader Alfred/Raycast-style actions                    | Depends on provider                                     |
| Snippets/custom keywords     | No equivalent general built-in snippet/quicklink UI   | Built-in snippets, quicklinks, aliases                  | Stronger general-purpose command/extension model        | Configurable providers/custom commands                  |
| Custom automation            | Native QML/JS provider, or Omarchy menu action         | Parameterized Raycast-format scripts plus extensions    | Script commands and Raycast-compatible extensions        | Custom command/provider configuration                   |
| Raycast extensions           | Native ports of selected extensions, not a React host | Own Node runtime for compatible Raycast extensions      | Broad Raycast-compatible ecosystem; not every Mac API    | Not a Raycast host                                      |
| Voice/AI                     | Optional Voxtype; deep Codex integration               | Generic AI endpoints and script/extension integration   | Optional capabilities through its ecosystem             | Backend/provider dependent                              |
| Default extra model/runtime  | Smart Match defaults on and fetches a pinned 8 MB model| No embedding model; Node only needed for extensions     | Separate launcher runtime                               | Separate frontend/backend processes                     |
| Linux ARM64 route            | QML native; Rust matching helper builds locally        | QML/JS; ARM Node available; not live-tested here         | Latest release includes an aarch64 AppImage              | Latest upstream release artifact is x86_64; build needed |

The table deliberately does not rank memory use from implementation language. We have not benchmarked equal workloads across all four launchers.

## What Keystroke does particularly well

### It fits the desktop rather than duplicating it

Keystroke runs inside `omarchy-shell`, follows its palette, fonts and layout tokens, understands the stock menu and our JSONC additions, and resolves existing menu routes. Our Everforest dark/light actions would be available without building another integration. It also exposes desktop keybindings as searchable actions, useful while learning Omarchy.

Unlike a separate popup bound to a new shortcut, enabling Keystroke changes `Super+Space`, other menu routes, and the menu's input/select pickers. Its manifest declares `omarchy.clonedFrom: "omarchy.menu"`. The documented reversal is `omarchy plugin disable evindor.keystroke`, which restores the stock menu. This is a broad but reversible desktop change, not merely an extra app.

### Its search is more capable than simple substring matching

The lexical matcher handles abbreviations and breadcrumb paths, frecency and query-specific preferences. Smart Match supplements it with a local Model2Vec embedding helper. Results still require explicit activation; semantic matching does not execute a guessed command.

The Small model is about 8 MB, the Large model about 31 MB. The upstream measurements for the compiled Small helper are about 16 MiB resident; the Python fallback is substantially larger. Those are upstream figures, not measurements on this Mac. Its advertised x86_64 prebuilt does not apply here, but its locked Rust source compiles successfully for aarch64. We already have the required Cargo toolchain.

The model is not needed for ordinary fuzzy search. Choosing Matching Off terminates the helper, while lexical matching remains. The helper also unloads after two idle minutes.

### Its optional features are genuinely optional

The ten bundled community extensions are off until explicitly enabled, and the registry avoids instantiating disabled extension services. Browser history, translation, GIF search, currency, timers, windows and other integrations can be added selectively. A custom extension is a QML/JS provider, not an arbitrary Raycast package drop-in.

Core local search does not send queries to remote AI. Initial model download needs network access. Enabled integrations have their own privacy behavior: Translate sends text to Google after a typing pause, GIF search uses a Raycast-operated GIPHY proxy, and explicit assistant handoffs send the prompt to the selected service. None should be treated as a security sandbox.

## Where Keystroke falls short for our workflow

### File search is not Spotlight

It searches file and folder names/paths, not document contents. Each distinct query walks the home directory with fd; it caps candidates at 400, uses two threads and a three-second watchdog, and caches only within one summon. Broad queries can return partial results before reaching the most relevant deep file. Gitignore and hidden-file settings matter; our newly hidden `~/.dotfiles` will not appear with hidden files disabled.

Its built-in file actions are narrower than Alfred's, Omarchy Files', or Omarchy Launcher's. The open issue requesting Copy Path reflects a real gap in the current version. A source/docs search with Telescope or ripgrep remains useful for our wiki and research code.

### It is not an Alfred workflow importer

We can add a fixed Omarchy menu action easily, and write a small QML provider for more elaborate commands. That is different from a built-in UI for user-defined search keywords, quicklinks, argument-taking scripts and snippets. Keystroke has an open feature request for deterministic aliases. Omarchy Launcher and Vicinae are better fits when these are everyday requirements.

No candidate imports every Alfred workflow unchanged. Workflows using AppleScript, `defaults`, `pbcopy`, or macOS application APIs need Linux adaptations regardless of launcher.

### Voice needs to respect SpaceFN

Our accepted Kanata configuration consumes a long held Space and enters navigation after 180 ms. Hyprland therefore cannot use that same physical Super+Space hold as Keystroke's long-press microphone trigger. We should keep its hold-to-talk bindings uninstalled.

Voxtype is already on this machine's PATH. Keystroke enables voice integration automatically when it detects that executable, and its default second launcher tap starts recording rather than closing. For familiar launcher behavior we should set Voice Off and second-tap behavior to Close. A separate non-Space hotkey is an option later.

Keyboard Cleaner is another extension to leave off until reviewed with the real/virtual Kanata devices and the palm guard. There is no reason to introduce a second input-disabling mechanism during this trial.

### Codex is not Pi

Its rich in-palette assistant is Codex-specific and needs a compatible Codex CLI plus Codex authentication. Our GitHub Copilot login in Pi does not grant Codex access. Given how much of our coding workflow already lives in Pi/tmux, this is optional rather than a reason by itself to choose Keystroke. A normal launcher action can open our Pi workflow.

## How the alternatives compare

### Omarchy Launcher

Its main advantages remain user-facing quicklinks, snippets, parameterized scripts, richer file actions, file-content search, and its own Raycast-compatible runtime. It runs alongside the stock menu, making an isolated-hotkey trial straightforward. Extensions require Node/esbuild and run unsandboxed; a source build and dependency lock are useful provenance, not isolation. This is a much smaller project than Vicinae, so the breadth of its README should not be mistaken for proven compatibility with every extension.

Keystroke is the cleaner choice if we value close stock-menu parity and native Omarchy behavior over an extensible command-hub interface. Omarchy Launcher is better if Alfred's Powerpack features are the real requirement and we want them inside Quickshell.

### Vicinae

Vicinae has the larger independent project/ecosystem, strong native command-palette features, script commands and Raycast compatibility. Its current release directly provides an aarch64 Linux AppImage. It is worth preferring if launcher workflows should be independent of Omarchy or if we repeatedly hit Keystroke's custom-command/file-action limitations.

The tradeoff is another application/service, a separately maintained Everforest theme, and explicit integration of our Omarchy actions. We should not assume every Raycast extension works: macOS-only binaries, APIs and OAuth redirects still impose limits.

### Walker + Elephant

This is a good configurable, provider-oriented choice, not a poor launcher. But on this Quickshell-based Omarchy installation it adds a different frontend/backend stack and theme integration, while upstream's current Walker release lists only an x86_64 binary. It is less compelling as the first trial on our ARM Mac than it was as a generic Linux recommendation. Source builds remain possible; lack of a prebuilt is not lack of ARM source compatibility.

### Omarchy Files + Web Launcher

These remain the smaller additions if we want to keep the stock menu. Omarchy Files has richer file actions than Keystroke's built-in provider; Web Launcher offers remembered search-engine selection and bookmarks. The cost is several separate overlays rather than Alfred's single command hub.

## Checks performed here

- Installed platform: Omarchy 4.0.3rc4-1.1, Quickshell 0.3.2, Qt 6.12.0, ARM64.
- Keystroke manifest validation succeeded without enabling it.
- Lexical matching test suite: 11 passed, including a reported 10.83 ms per query over 700 synthetic menu rows on this machine.
- File query test suite: 10 passed, including literal/bounded argv construction and filename handling; its synthetic 400-candidate ranking reported 7.35 ms per query.
- The matching engine built with `cargo build --release --locked` and produced an aarch64 ELF binary in the temporary research directory.
- No model was downloaded, no plugin was installed/enabled, and no desktop keybindings were changed for this comparison.

These microbenchmarks exclude filesystem scans, model loading, the complete UI and real-world display behavior. They are compatibility evidence, not a claim that Keystroke is globally faster than the alternatives. Open issues currently include slow/FUSE file walks affecting actions, missing Copy Path, aliases and sizing behavior. We should check the UI at our display scale before making it the permanent menu.

## Sources

- [Keystroke README and release](https://github.com/evindor/keystroke/tree/v1.5.1)
- [Architecture and bounded file search](https://github.com/evindor/keystroke/blob/v1.5.1/docs/architecture.md)
- [Smart Match runtime](https://github.com/evindor/keystroke/blob/v1.5.1/matching/README.md)
- [Engine provenance](https://github.com/evindor/keystroke/blob/v1.5.1/docs/engine-provenance.md)
- [Current Keystroke issues](https://github.com/evindor/keystroke/issues)
- [Omarchy Launcher](https://github.com/hominluo/omarchy-launcher)
- [Vicinae](https://github.com/vicinaehq/vicinae)
- [Walker](https://github.com/abenz1267/walker) and [Elephant](https://github.com/abenz1267/elephant)
- [Omarchy Files](https://github.com/crmne/omarchy-files) and [Web Launcher](https://github.com/greenspotmail/omarchy-weblauncher)
