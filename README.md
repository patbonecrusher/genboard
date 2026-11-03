# Genboard

A macOS research workbench for genealogy: browse FamilySearch, WikiTree, Find a Grave and
Drouin inside research sessions, pin pages with a note on why they matter, mark dead ends,
and write where you left off when you close a session. See [DESIGN.md](DESIGN.md).

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Genboard.xcodeproj        # or:
xcodebuild -scheme Genboard -derivedDataPath build build && open build/Build/Products/Debug/Genboard.app
```

`project.yml` is the source of truth; regenerate the Xcode project after adding files.

## AI assistant

Add an Anthropic API key in Settings (⌘,). It is stored in the macOS Keychain
(`ANTHROPIC_API_KEY` in the environment also works). Default models: Claude Opus 5.5 for
questions and record transcription, Claude Haiku 5.5 for session summaries; change them per
feature in Settings. The assistant panel shows the running cost for each session.

## Research board

Each project has a board (⌘2): person, event, evidence and note cards with typed connections
(spouse, parent, child, supports, contradicts). Drag pinned pages from the Timeline onto it,
shift-click to connect cards, and use **Import Scapple…** to bring in existing `.scap` boards.

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
