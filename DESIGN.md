# Genboard — Design

A macOS research workbench for genealogy. Not a family-tree editor: it tracks
*where* you looked, *what* each source says, *where sources disagree*, and
*what you suspect but haven't proven yet*.

## Problem

A typical research afternoon: start from a Find a Grave memorial, jump to
FamilySearch, cross-check WikiTree, validate in Drouin. It ends with 20 tabs,
loose screenshots, and hypotheses that live only in your head.

## Concepts

```
Project ──< Session ──< Visit (page history, auto)
   │                       │
   │                       └─ pinned? → Source (+ "why it matters" note, screenshot)
   │
   ├──< Person ──< Claim >── Source
   └──< Hypothesis ──< Evidence (for/against → Claim or Source)
                   └──< Todo
```

| Entity | Meaning |
|---|---|
| **Project** | One research effort, e.g. "Marie's paternal line". |
| **Session** | One sitting of research inside a project. Has a goal ("find parents of Joseph Morel"), start/end time, and a closing summary. Restores its open tabs when resumed. |
| **Visit** | Every page loaded in the in-app browser during a session: URL, title, site, timestamp. Recorded automatically. |
| **Source** | A visit you pinned because it matters. Holds a note on *why it's important*, a screenshot, selected text, and an optional record ID (FamilySearch PID, WikiTree ID, Find a Grave #, Drouin ref). |
| **Claim** | A single statement taken from one source ("father = Jean Morel"). Belongs to a person. |
| **Person** | Your conclusion that several claims describe the same individual. |
| **Hypothesis** | A suspicion with status (open / supported / refuted), evidence for and against, and next steps. |

### Visit states

Each visit in the session history can be marked:

- **Pinned** — important; becomes a Source with a "why" note.
- **Dead end** — checked, nothing useful (note optional). Prevents redoing a search.
- **Unmarked** — kept in history, shown collapsed.

### Closing and resuming a session

**Close prompt.** Ending a session (explicit *End Session*, switching
session, or quitting the app) opens a sheet before closing:

- Read-only recap: session goal, duration, pages pinned this session (with
  their why-notes), and how many dead ends were marked.
- **Where I left off** — free text (required; can be dismissed with "skip"
  but the session is then flagged *no summary*).
- **Next steps** — one per line; each becomes a Todo on the project.
- **Open questions** — optional; can be promoted to a Hypothesis.
- **Keep tabs** toggle (default on) — save open tabs for resume.

**Resume.** Reopening a session (or opening its project) shows a "Last time"
banner at the top of the browser: the where-I-left-off text, next steps as
checkboxes, and a *Reopen tabs* button. The project sidebar shows the latest
summary line under each session.

Later: AI-drafted summary from the session's pins and notes, for you to edit.

## Main screens

1. **Project sidebar** — projects → sessions, people, hypotheses.
2. **Browser** — tabbed WKWebView scoped to the current session. Logins persist
   (shared website data store). Toolbar: *Pin* (⌘P-style hotkey) opens a small
   popover: why-note, auto screenshot, selected text, link to person.
3. **Session timeline** — chronological list of visits with pins/dead ends
   highlighted and their notes; session goal at the top, summary at the bottom.
4. **Person comparison grid** — rows = facts (birth, death, parents, spouse,
   marriage), columns = sources. Disagreements highlighted.
5. **Hypothesis board** — open / supported / refuted, each with evidence and todos.

## Build order

1. **MVP** — Projects, sessions, in-app tabbed browser, automatic visit
   history, pin with why-note + screenshot, dead-end marking, session timeline,
   close-session summary prompt, resume with "Last time" banner + reopen tabs.
2. People + claims + comparison grid with conflict highlighting.
3. Hypotheses with evidence links and todos.
4. Later: AI extraction from screenshots, per-site record-ID parsing, pedigree
   view, GEDCOM export.

## Research board

One board per project (Browse/Board switch, ⌘1/⌘2): a freeform canvas like a
Scapple board, but with typed cards so the app understands it.

| Card | Holds |
|---|---|
| Person | name, life dates, place, notes |
| Event | baptism/marriage/burial/census: title, date, place |
| Evidence | a pinned page (screenshot, URL, note, transcription) or an imported image |
| Note | free text; flag as Question or Conflict |

Connections have roles, read "from → to": related, spouse of, parent of,
child of, supports (green), contradicts (red, dashed). Shift-click a card to
connect the selected card to it; roles are edited in the card editor.

- Drag a pinned page from the Timeline onto the board to make an evidence card.
- Import a Scapple `.scap` board: notes become note cards (keeping position and
  fill color), lines and arrows become connections. Image import is best effort.
- The board (cards, flags, connections) is part of the AI's research context.
- Pure SwiftUI canvas (Canvas for lines, offset cards, pan/zoom gestures): no
  AppKit-backed lists or split views, which caused the layout-loop crashes.

### Theories (hypotheses)

A theory is a named statement ("Olivine's father is Pierre Girard") with a
status (open / supported / refuted), reasoning, a color, and its own to-dos.
Cards and connections can belong to several theories, so competing versions
share the facts they agree on.

- Clicking a theory makes it active: other cards dim, and cards and
  connections added while it's active go into it (a connection brings both
  ends). Membership is also a checkbox per theory in the card editor.
- Drawing: open = dashed border in the theory's color, supported = solid,
  all-theories-refuted = greyed out. Hiding a theory hides cards that belong
  only to hidden theories; cards outside any theory always show.
- Evidence for / against is derived: cards with a "supports" / "contradicts"
  link into the theory's cards, plus conflict-flagged cards in the theory.
- Theories, their status, evidence and to-dos are in the AI context; the
  assistant is told to weigh them and name the record that would settle each.

### AI card suggestions

"Suggest Cards with AI" on an evidence card (or a note holding record text)
sends the screenshot, transcription and notes plus the people already on the
board to the transcription model with a JSON schema (people with role, dates,
place and an optional match to an existing card; events with participants;
parent/child/spouse relationships). A review sheet lists everything with
checkboxes; nothing is added until the researcher clicks Add. Added cards go
under the record, each linked to it with "supports"; matched people are
reused instead of duplicated; participants link to events with their role as
the label. Cards join the active theory, like any other add.

### Checks

Local, free, recomputed on every change (BoardChecks): compares years on
person cards ("1861–1934", "b. ~1862", "d. 1888") and event cards along their
connections. Flags: born after death; baptism/birth or burial/death events
that disagree with stated dates; appearing in an event after death or before
birth; married under 13; parent under 13 or over 70 at a child's birth; child
born after a parent died; two person cards with the same name and compatible
births that aren't connected. Marriage checks only apply to people connected
as a spouse (role or a label like groom/bride/époux), since boards often hang
children off their parents' marriage. Results: the Checks panel (count badge
on the toolbar) and a warning mark on affected cards.

### Family tree and GEDCOM

The **Tree** view (⌘3) is generated from person cards and their parent /
child / spouse connections (FamilyGraph). Ancestors (pedigree) or
descendants, 2–10 generations, from any person (double-click to re-root).
Each person sits centered on the span of the relatives they lead to; people
reached twice are drawn twice, as on paper charts. Competing parents from
different theories are all drawn, in their theory colors; refuted ones greyed.
Hidden theories stay hidden.

**GEDCOM 5.5.1 export** (button in the tree toolbar): individuals with SEX,
BIRT/DEAT from life dates (ABT for "~"), BAPM/BIRT and BURI/DEAT from linked
event cards (dates converted from French or English, e.g. "20 novembre 1855"
→ "20 NOV 1855"), notes, theory membership as notes; families from parent
sets and spouse pairs, with MARR from a marriage event linked to both
spouses; evidence cards that "support" a person become SOUR records with the
URL and transcription. Refuted and hidden theories are left out; a child with
more than two parents on the board exports the first two plus a note naming
all candidates. Person cards gained a Sex field (set from roles by the AI
suggestions) so parents can be placed as HUSB/WIFE.

## Not built yet

- Importing GEDCOM or FamilySearch trees onto the board.
- Local MLX model as a second AI provider (summaries, privacy).

## AI assistant

A side panel that answers questions *with the current project as context*
(session goal, pins + why-notes, claims, hypotheses, the open page's text or
screenshot).

Uses:
- Ask questions: "Do FamilySearch and WikiTree agree on Joseph's father?"
- Read/transcribe a Drouin record screenshot (old French handwriting) and
  propose claims.
- Draft the close-session summary from pins and notes.
- Suggest next searches for an open hypothesis.

Design rules:
- AI output is always a *suggestion* you accept/edit; never silently written
  as a claim.
- Every answer cites which pins/sources it used.
- `AIProvider` protocol so backends are swappable: Claude API first
  (URLSession + API key in Keychain; no official Swift SDK), local MLX later.
- Per-feature model setting (chat vs. extraction vs. summary) and a running
  token/cost counter per session.
- Defaults: Opus 5.5 for questions and transcription, Haiku 5.5 for summaries
  (structured JSON output). Opus/Sonnet requests opt into server-side refusal
  fallbacks (`fallbacks: "default"`).
- The project context snapshot is sent inside each user turn, not the system
  prompt, so the conversation stays append-only (prompt caching works, and
  replayed thinking blocks stay valid).
- Local MLX is the planned second provider (64GB Mac makes 30B-class models
  practical) for summaries and private work.

## Tech

- SwiftUI + SwiftData, macOS 15+.
- WKWebView for browsing; `WKWebView.takeSnapshot` for screenshots.
- Screenshots stored as files in the app container, referenced from SwiftData.
- Local-first; iCloud sync optional later.

## Non-goals

- Full family-tree editing.
- Automated scraping of FamilySearch / Drouin (terms of service). Capture is
  user-driven while browsing.
