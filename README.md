# Genboard

A macOS research workbench for genealogy: browse FamilySearch, WikiTree, Find a Grave and
Drouin inside research sessions, pin pages with a note on why they matter, mark dead ends,
and write where you left off when you close a session. See [DESIGN.md](DESIGN.md).

Website: https://patbonecrusher.github.io/genboard/

## Install

```sh
brew install --cask patbonecrusher/tap/genboard
```

Or download the signed, notarized zip from [Releases](https://github.com/patbonecrusher/genboard/releases/latest).
Requires macOS 15 or later (Apple silicon or Intel).

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Genboard.xcodeproj        # or:
xcodebuild -scheme Genboard -derivedDataPath build build && open build/Build/Products/Debug/Genboard.app
```

`project.yml` is the source of truth; regenerate the Xcode project after adding files.

The app icon is drawn in code by `tools/make_icon.swift`; run `tools/make_icon.sh` after editing it
to regenerate every size in `Genboard/Assets.xcassets/AppIcon.appiconset`.

## Releasing

`tools/ship.sh` does it all: it bumps `MARKETING_VERSION` (next minor version, or `tools/ship.sh 0.2.1`)
and `CURRENT_PROJECT_VERSION`, checks `RELEASE_NOTES.md`, commits, pushes and runs `tools/release.sh`.
If the notes aren't for the new version yet, it drafts them from the commits since the last release
and stops so you can edit them; run it again to ship. It refuses when nothing in the app changed.

By hand:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (Sparkle compares the build number) in
   `project.yml` and write `RELEASE_NOTES.md`; commit.
2. `tools/release.sh` builds a universal Release app signed with the Developer ID certificate and the
   hardened runtime (re-signing Sparkle's helpers too), notarizes and staples it, tags `v<version>`,
   publishes the GitHub release with `build/Genboard-<version>.zip`, adds the signed update to the
   Sparkle feed `docs/appcast.xml` and pushes it, and updates `Casks/genboard.rb` in the Homebrew tap
   at `$TAP_DIR`. `tools/release.sh --dry-run` stops after notarizing.

The Sparkle signing key is in the login keychain (created by Sparkle's `generate_keys`; its public
half is `SUPublicEDKey` in `project.yml`). Keep a copy: `generate_keys -x sparkle-key.txt` (the tool
is in `build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/`). Without it, no further update
can be published to existing installs.

`TEAM_ID`, `TAP_DIR` and the notarization credentials (`ASC_KEY_ID`/`ASC_ISSUER_ID`, or a
`NOTARY_PROFILE`) come from the environment, `~/.config/mac-app-kit/defaults.env` or `.release.env`.

## Tests

`tools/test.sh` runs the unit tests (Swift Testing, in `GenboardTests/`); `tools/test.sh SearchTests`
runs one suite. They cover the checks, family graph, GEDCOM export and import, Scapple import,
evidence weighting, line hit-testing, reports, search, backups and the local-model client. Tests run
against an in-memory store, never the real one. `LiveLocalModelTests` talk to a real
`mlx_lm.server` and only run when given one:
`TEST_RUNNER_GENBOARD_LOCAL_URL=http://127.0.0.1:8080 tools/test.sh LiveLocalModelTests`.

## Website

`docs/` is published to GitHub Pages by `.github/workflows/pages.yml` on every push that changes it.

- `python3 tools/build_site.py` rebuilds the pages (shared header and footer).
- `tools/build_site_assets.sh` regenerates the icons and social card.
- `tools/capture_screenshots.sh` retakes the screenshots from a fictional demo project
  (`-GenboardDemo YES`, Debug builds only, in-memory store), after a Debug build.

## AI assistant

Add an Anthropic API key in Settings (⌘,). It is stored in the macOS Keychain
(`ANTHROPIC_API_KEY` in the environment also works). Default models: Claude Opus 5.5 for
questions and record transcription, Claude Haiku 5.5 for session summaries; change them per
feature in Settings. The assistant panel shows the running cost for each session.

Questions and summaries can also run on a local model (free, private): start `mlx_lm.server`
(`uv tool install mlx-lm`, then `mlx_lm.server --model mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit`)
and choose "Local model (MLX)" for a task in Settings.

## Research board

Each project has a board (⌘2): person, event, evidence and note cards with typed connections
(spouse, parent, child, supports, contradicts). Drag pinned pages from the Timeline onto it,
drag the round handle on a card's edge onto another card to connect them (or shift-click), click a
line to edit the connection, and use the import button to bring in a GEDCOM family tree or a Scapple
board. Evidence cards hold a citation and a source-quality rating (original / derivative / authored,
primary / secondary) that weighs each theory's evidence.

**Reports** (⇧⌘R) export a project or a theory as PDF, Markdown or HTML. **Search** (⇧⌘F) covers every
project. **File ▸ Export Project… / Back Up All Projects… / Restore from Backup…** save and restore
`.genboard` files.

**Theories** (lightbulb button) track competing hypotheses, e.g. two candidate fathers. Click a
theory to make it active; what you add or connect goes into it. Each has a status, evidence for
and against (from "supports"/"contradicts" connections), and its own to-dos.

**Suggest Cards with AI** (on an evidence card) reads the record and proposes people, events and
relationships for you to review; matches people already on the board instead of duplicating them.
**Checks** flags date contradictions (burial before stated death, appearing after death, married
too young, implausible parent ages) and possible duplicate people. Checks run locally and are free.

## Family tree and GEDCOM

The **Tree** view (⌘3) draws ancestors or descendants from the board's parent/child/spouse
connections, including competing parents from different theories. **GEDCOM** (tree toolbar) exports
people, families, events and evidence sources for FamilySearch, Ancestry, Gramps or MacFamilyTree;
refuted and hidden theories are left out.

## Testing

Debug builds accept `-GenboardSmokeTest YES`: an in-memory store (your data is untouched) and a
timer that resizes the window, moves focus, churns tabs, pins, opens sheets, switches sessions and
edits the board. Add `-GenboardSmokeImport /path/to/board.scap` to import a Scapple file first.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘1 / ⌘2 / ⌘3 | Browser / research board / family tree |
| ⌘T | New tab |
| ⌘D | Pin page (screenshot + selected text + note) |
| ⇧⌘D | Mark / unmark dead end |
| ⇧⌘E | End session (summary prompt) |
