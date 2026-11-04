#!/usr/bin/env python3
"""Builds the website pages in docs/ from the page bodies below, with a shared header and footer.

    python3 tools/build_site.py
"""
from pathlib import Path

SITE = "https://patbonecrusher.github.io/genboard/"
REPO = "https://github.com/patbonecrusher/genboard"
DOCS = Path(__file__).resolve().parent.parent / "docs"
EFFECTIVE = "3 November 2026"

NAV = [("./", "Overview"), ("help.html", "Help"), ("privacy.html", "Privacy"), ("terms.html", "Terms")]


def page(filename, title, description, body):
    nav = "".join(
        f'<a href="{href}"{" aria-current=\"page\"" if href == filename or (href == "./" and filename == "index.html") else ""}>{label}</a>'
        for href, label in NAV
    )
    url = SITE + ("" if filename == "index.html" else filename)
    html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="icon" href="icon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="icon-64.png" sizes="64x64" type="image/png">
<link rel="apple-touch-icon" href="icon-180.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Genboard">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{url}">
<meta property="og:image" content="{SITE}social-card.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="stylesheet" href="style.css">
</head>
<body>
<header class="site"><div class="inner">
  <a class="brand" href="./"><img class="mark" src="icon-64.png" alt="" width="36" height="36">Genboard</a>
  <nav>{nav}<a href="{REPO}">GitHub</a></nav>
</div></header>
<main>
{body.strip()}
</main>
<footer class="site"><div class="inner">
  <a href="./">Overview</a><a href="help.html">Help</a><a href="privacy.html">Privacy Policy</a><a href="terms.html">Terms of Service</a><a href="{REPO}">Source</a>
  <p>Genboard is an independent project by Patrick Laplante. It is not affiliated with FamilySearch, WikiTree, Find a Grave, Généalogie Québec or Anthropic; their names are trademarks of their owners. Claude is a trademark of Anthropic. Mac and macOS are trademarks of Apple Inc. The people in the screenshots are fictional.</p>
</div></footer>
</body>
</html>
"""
    (DOCS / filename).write_text(html, encoding="utf-8")


page("index.html", "Genboard: a research workbench for genealogy",
     "Genboard is a native macOS app for family-history research: browse genealogy sites in research sessions, test competing theories on a board, and export a family tree as GEDCOM.",
     f"""
<img class="hero-icon" src="icon-512.png" alt="Genboard app icon" width="132" height="132">
<h1>Genboard</h1>
<p class="lede">A native macOS workbench for family-history research. Browse FamilySearch, WikiTree, Find a Grave and the Drouin collection in research sessions, keep track of what each source says, test competing theories on a board, and export the result as a family tree.</p>

<div class="install">
  <div class="card">
    <h3>Homebrew</h3>
    <p>Installs the app. It keeps itself up to date.</p>
    <pre><code>brew install --cask patbonecrusher/tap/genboard</code></pre>
  </div>
  <div class="card">
    <h3>Direct download</h3>
    <p>Signed and notarized by Apple. Unzip and drag to Applications; updates arrive on their own.</p>
    <a class="button" href="{REPO}/releases/latest">Download Genboard</a>
  </div>
</div>
<p class="meta">Requires macOS 15 Sequoia or later, on Apple silicon or Intel. Genboard is in early development, so expect rough edges. You can also <a href="{REPO}#build">build it from source</a>.</p>

<div class="shots">
  <figure><img src="screenshot-1.png" alt="The research board: person, event, evidence and note cards connected by parent, spouse, supports and contradicts lines, with a Theories panel and a Checks panel" width="2400" height="1500"><figcaption>The research board: people, events and records connected by what they mean, two competing theories about a father, and a check that caught a burial dated before the death.</figcaption></figure>
  <figure><img src="screenshot-2.png" alt="A pedigree chart with both candidate fathers drawn in their theory colors" width="2400" height="1500"><figcaption>The family tree is built from the board. Competing parents appear side by side in their theory's color.</figcaption></figure>
  <figure><img src="screenshot-3.png" alt="The browser with a Last time banner, to-dos, and a timeline of pinned pages with notes" width="2400" height="1500"><figcaption>Research sessions remember every page, the ones you pinned and why, and where you left off last time.</figcaption></figure>
</div>

<h2>What it does</h2>
<div class="grid">
  <div class="card"><h3>Research sessions</h3><p>A built-in browser keeps every page you open in the session's history, so twenty tabs and a folder of screenshots become one timeline.</p></div>
  <div class="card"><h3>Pins and dead ends</h3><p>Pin a page with <kbd>⌘D</kbd> to save a screenshot, the text you selected and a note on why it matters. Mark searches that led nowhere so you don't repeat them.</p></div>
  <div class="card"><h3>Pick up where you left off</h3><p>Closing a session asks where you stopped, what's next and what's still open. The next session starts with that note and its to-dos.</p></div>
  <div class="card"><h3>A board for the evidence</h3><p>Person, event, evidence and note cards, connected as parent, spouse, child, <em>supports</em> or <em>contradicts</em>. Drag pinned pages straight onto it.</p></div>
  <div class="card"><h3>Competing theories</h3><p>Track rival explanations, such as two candidate fathers, side by side. Each has a status, evidence for and against weighed by source quality, and its own to-dos.</p></div>
  <div class="card"><h3>Citations and source quality</h3><p>Give each record a full citation and rate it: original, derivative or authored, with primary or secondary information. A parish register counts for more than an online tree.</p></div>
  <div class="card"><h3>Checks</h3><p>Catches burials dated before a stated death, people appearing after they died, marriages at ten and implausible parent ages. They run locally and cost nothing.</p></div>
  <div class="card"><h3>Family tree and GEDCOM</h3><p>Ancestor and descendant charts built from the board. Import a GEDCOM tree from FamilySearch or Ancestry to start from, and export people, families, events and cited sources back out.</p></div>
  <div class="card"><h3>Reports and search</h3><p>Export a theory or a whole project as a PDF report to share. Search every page, note, transcription, card and citation at once with <kbd>⇧⌘F</kbd>.</p></div>
  <div class="card"><h3>Claude or a local model</h3><p>With your own Anthropic API key, ask questions, transcribe handwritten parish records, and turn a record into suggested cards you review first. Or run questions and summaries on a free model on your own Mac.</p></div>
  <div class="card"><h3>Scapple boards</h3><p>Import existing Scapple boards. Notes keep their places and colors, and lines and arrows become connections.</p></div>
  <div class="card"><h3>Backups</h3><p>Save a project, or all of them, as one file with every page, screenshot, card and theory, and restore it on any Mac.</p></div>
</div>

<div class="card accent">
  <p><strong>Your research stays on your Mac.</strong> Genboard has no accounts and no analytics, and the developer never receives your data. The only thing that leaves your Mac is what you send to Claude when you use the AI features, with your own API key. See the <a href="privacy.html">Privacy Policy</a>.</p>
</div>

<h2>Contact</h2>
<p>Bug reports and feature requests are welcome on <a href="{REPO}/issues">GitHub Issues</a>. The source code is on <a href="{REPO}">GitHub</a>.</p>
""")

page("help.html", "Help · Genboard",
     "How to use Genboard: research sessions, pins, the research board, theories, citations, checks, the family tree, GEDCOM, reports, search, backups and the AI assistant.",
     """
<h1>Help</h1>
<p class="lede">How Genboard is organized, and how to use each part.</p>

<h2>Projects and sessions</h2>
<p>A <strong>project</strong> is one research effort, such as one family line. Inside it, a <strong>session</strong> is one sitting of research with a goal, like “Find Émilie's father”. Create a project with <strong>New Project</strong> at the bottom of the sidebar, then start a session from it. Click an earlier session in the sidebar to resume it; its tabs reopen.</p>

<h2>Browsing</h2>
<p>Use <strong>Browse</strong> (<kbd>⌘1</kbd>) to work in the built-in browser. The <strong>Sites</strong> menu and the start page open FamilySearch, WikiTree, Find a Grave and Généalogie Québec. Your logins are remembered between launches. Every page you open is recorded in the session's <strong>Timeline</strong> (right-hand panel).</p>
<ul>
  <li><strong>Pin</strong> a page with <kbd>⌘D</kbd>: Genboard saves a screenshot and any text you selected, and asks why the page matters.</li>
  <li><strong>Mark a dead end</strong> with <kbd>⇧⌘D</kbd> when a page was checked and had nothing useful.</li>
  <li>The Timeline shows pins and dead ends. Check <em>Show all pages</em> to see everything. Right-click a page to edit its note, transcribe it with AI, or open it in a new tab.</li>
</ul>

<h2>Ending a session</h2>
<p><strong>End Session</strong> (<kbd>⇧⌘E</kbd>) asks where you left off, your next steps (each becomes a to-do) and open questions, and whether to keep the open tabs. The same prompt appears when you switch sessions or quit. Next time, a <strong>Last time</strong> banner shows that note and the to-dos.</p>

<h2>The research board</h2>
<p>Use <strong>Board</strong> (<kbd>⌘2</kbd>). Each project has one board.</p>
<ul>
  <li><strong>Add cards</strong> from <strong>+ Add</strong>: Person, Event (baptism, marriage, burial, census…), Note, or Evidence from a pinned page. You can also drag a pinned page from the Timeline onto the board.</li>
  <li><strong>Edit</strong> a card by clicking it. Flag a card as a <em>Question</em> or a <em>Conflict</em>.</li>
  <li><strong>Connect</strong> two cards by dragging the round handle on a card's edge onto the other card, or select one and shift-click the other.</li>
  <li><strong>Click a connection line</strong> (or its label) to edit it: what it means (<em>related</em>, <em>spouse of</em>, <em>parent of</em>, <em>child of</em>, <em>supports</em> or <em>contradicts</em>), its direction, a label for the line, a note on why it's there, and which theories it belongs to. The card editor lists a card's connections too.</li>
  <li><strong>Move</strong> cards by dragging them, pan by dragging the background, and zoom with the toolbar or a pinch.</li>
</ul>

<h2>Citations and source quality</h2>
<p>Every evidence card has a <strong>Source</strong> section: a full citation (record, date, place, page or folio), the repository, and two ratings from the Genealogical Proof Standard:</p>
<ul>
  <li><strong>Source</strong>: <em>Original</em> (the record itself or an image of it, like a Drouin parish register page), <em>Derivative</em> (an index, transcription or abstract) or <em>Authored</em> (someone's conclusions, like an online tree or a memorial).</li>
  <li><strong>Information</strong>: <em>Primary</em> (from someone who was there, like the priest at a baptism) or <em>Secondary</em> (heard from others, like an age at death).</li>
</ul>
<p>Genboard guesses the source type from the site when you add a record, so a Drouin image starts as original and a WikiTree profile as authored. Change it whenever you know better. The ratings show on the card, weigh each theory's evidence, and go into the GEDCOM export and reports.</p>

<h2>Theories</h2>
<p>Click <strong>Theories</strong> on the board toolbar. A theory is a statement you're testing, like “Émilie's father is Antoine Tremblay”. Press <strong>+</strong> to start one (it begins with the selected card), then click it to make it active: other cards dim, and the cards and connections you add go into it. A card can belong to several theories, so competing versions share the facts they agree on.</p>
<p>Set a theory's status to <em>Open</em>, <em>Supported</em> or <em>Refuted</em>. Its cards show a <span class="theory">dashed border</span> while it's open and a solid one once supported; cards that belong only to refuted theories are greyed out. Each theory lists its evidence for and against (from <em>supports</em> and <em>contradicts</em> connections) and has its own to-dos. Use the eye button to hide a theory.</p>
<p>The bars beside each theory show the <strong>weight of its evidence</strong>: one original record with primary information counts fully, an online tree about a quarter, a note of your own a fifth. A theory reads <em>Strong</em>, <em>Fair</em> or <em>Weak</em>, or <em>Contested</em> when the evidence against comes close to the evidence for. It's a guide for where to look next, not a verdict.</p>

<h2>Checks</h2>
<p><strong>Checks</strong> on the board toolbar compares the years on person and event cards along their connections, and shows a count when it finds something:</p>
<ul>
  <li>A burial or baptism that disagrees with a person's stated dates.</li>
  <li>Someone appearing in an event after their death or before their birth.</li>
  <li>A spouse under 13 at marriage, a parent under 13 or over 70 at a birth, or a child born after a parent died.</li>
  <li>Two cards with the same name that might be one person.</li>
</ul>
<p class="note">Write dates on person cards as “1861–1934”, “b. 1826”, “d. 1888” or “b. ~1862”. Marriage checks apply to people connected to the marriage as a spouse (the <em>spouse of</em> role, or a label such as groom, bride, époux or épouse), since boards often connect children to their parents' marriage.</p>

<h2>Family tree and GEDCOM</h2>
<p>Use <strong>Tree</strong> (<kbd>⌘3</kbd>) for an ancestor or descendant chart built from the board's <em>parent of</em>, <em>child of</em> and <em>spouse of</em> connections. Pick the starting person from the menu, or double-click anyone in the chart. Competing parents from different theories are all shown in their theory colors.</p>
<p><strong>GEDCOM</strong> in the tree toolbar saves a GEDCOM 5.5.1 file for FamilySearch, Ancestry, Gramps or MacFamilyTree: people, births, baptisms, deaths, burials, marriages, families, and your evidence cards as sources with their citations and quality ratings. Refuted and hidden theories are left out. Set each person's <strong>Sex</strong> in the card editor so parents are placed as husband and wife.</p>
<p>To start from an existing tree, use the import button on the board toolbar and choose <strong>GEDCOM Family Tree…</strong>. People arrive as person cards laid out as a tree, with parents above their children, couples side by side (marriage year on the line), and the full dates, places, notes and source titles in each card's notes.</p>

<h2>Reports</h2>
<p><strong>Export Research Report</strong> (<kbd>⇧⌘R</kbd>, or right-click a project in the sidebar) writes up the whole project or a single theory for family or a genealogical society: each theory's status and weight of evidence, the evidence for and against with citations, connection notes, open questions, people, sources, and the research log of sessions and pinned pages. Save it as a PDF, Markdown or a web page.</p>

<h2>Search</h2>
<p><strong>Search All Research</strong> (<kbd>⇧⌘F</kbd>, or the magnifying glass at the bottom of the sidebar) looks through every project: pages and their notes, transcriptions, cards, citations, connection notes, theories, session summaries and to-dos. Case and accents don't matter, so “helene” finds Hélène. Every word must appear. Use the arrow keys and Return to open a result where it lives; a result in another project opens that project's latest session.</p>

<h2>The AI assistant</h2>
<p>The AI features are optional. They use Claude with your own Anthropic API key, added in <strong>Settings</strong> (<kbd>⌘,</kbd>) and stored in your Keychain, or a model running on your own Mac. Claude usage is billed to your Anthropic account; the Assistant panel shows the running cost of each session.</p>
<ul>
  <li><strong>Assistant</strong> (right-hand panel): ask questions. It sees your pins, notes, dead ends, to-dos, board, theories and earlier session summaries, plus the current page if you attach its text or a screenshot.</li>
  <li><strong>Transcribe with AI</strong> (right-click a pinned page): transcribes and translates a record and lists the people and events in it.</li>
  <li><strong>Suggest Cards with AI</strong> (on an evidence card): proposes people, events and relationships from the record. Nothing is added until you review the list and click Add.</li>
  <li><strong>Draft with AI</strong> (when ending a session): writes a first draft of your summary.</li>
</ul>
<p>Choose the model for each feature in Settings. See the <a href="privacy.html">Privacy Policy</a> for what is sent.</p>
<h3>A local model</h3>
<p>Questions and session summaries can run on a free model on your Mac with <a href="https://github.com/ml-explore/mlx-lm">MLX</a>, so nothing leaves the computer. In Terminal (the first run downloads about 17 GB; a Mac with 32 GB of memory or more is best):</p>
<pre><code>uv tool install mlx-lm
mlx_lm.server --model mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit</code></pre>
<p>Then in Settings, under <strong>Local model (MLX)</strong>, press <strong>Test Connection</strong> and choose <em>Local model (MLX)</em> for a task. LM Studio and Ollama work too; enter their address. Local models read text only, so keep Claude for transcribing handwritten records.</p>

<h2>Importing a Scapple board</h2>
<p>Click the import button on the board toolbar and choose a <code>.scap</code> file. Notes become note cards in the same places and colors, and lines and arrows become connections. Change a card's type afterwards in its editor.</p>

<h2>Keyboard shortcuts</h2>
<div class="table-wrap"><table>
  <tr><th>Action</th><th>Keys</th></tr>
  <tr><td>Browse / Board / Tree</td><td><kbd>⌘1</kbd> / <kbd>⌘2</kbd> / <kbd>⌘3</kbd></td></tr>
  <tr><td>New tab</td><td><kbd>⌘T</kbd></td></tr>
  <tr><td>Pin page</td><td><kbd>⌘D</kbd></td></tr>
  <tr><td>Mark or unmark a dead end</td><td><kbd>⇧⌘D</kbd></td></tr>
  <tr><td>End session</td><td><kbd>⇧⌘E</kbd></td></tr>
  <tr><td>Search all research</td><td><kbd>⇧⌘F</kbd></td></tr>
  <tr><td>Export research report</td><td><kbd>⇧⌘R</kbd></td></tr>
  <tr><td>Save a pin, or save and close a session</td><td><kbd>⌘↩</kbd></td></tr>
  <tr><td>Settings</td><td><kbd>⌘,</kbd></td></tr>
</table></div>

<h2>Backups and your data</h2>
<p>Everything is stored on your Mac, in <code>~/Library/Application Support/Genboard/</code> (the database and pinned screenshots).</p>
<p>In the <strong>File</strong> menu, <strong>Export Project…</strong> saves the current project, and <strong>Back Up All Projects…</strong> saves every project, as one <code>.genboard</code> file with its sessions, pages, screenshots, board, theories and to-dos. <strong>Restore from Backup…</strong> adds the projects in such a file next to yours; it never replaces anything, and a project whose name is taken comes back as “(restored)”. Use it to keep a copy somewhere safe or to move your research to another Mac.</p>

<h2>Updates</h2>
<p>The downloaded app checks for updates once a day and asks before installing one; <strong>Genboard ▸ Check for Updates…</strong> checks now. With Homebrew, the app updates itself the same way.</p>

<h2>Something wrong?</h2>
<p>Report it on <a href="https://github.com/patbonecrusher/genboard/issues">GitHub Issues</a>, with your macOS version and what you were doing when it happened.</p>
""")

page("privacy.html", "Privacy Policy · Genboard",
     "Genboard keeps your research on your Mac. The developer receives nothing; AI requests you make go to Anthropic with your own API key.",
     f"""
<h1>Privacy Policy</h1>
<p class="meta">Effective {EFFECTIVE}</p>

<div class="card accent">
  <p><strong>In short:</strong> Genboard keeps your research on your Mac, and the developer never receives your data or anything about how you use the app. Information leaves your Mac only when the built-in browser loads a website you visit, when you use a Claude AI feature, which sends your request to Anthropic with your own API key, and when the app checks for updates.</p>
</div>

<h2>Who this covers</h2>
<p>This policy describes how the Genboard application for macOS ("Genboard", "the app") handles information. Genboard is developed and maintained by an individual developer ("the developer").</p>

<h2>Information the developer collects</h2>
<p>None. Genboard has no accounts, analytics, telemetry, crash reporting or advertising, and it never sends anything to the developer. Update checks (below) download a public file and send nothing about you or your research.</p>

<h2>Information stored on your Mac</h2>
<div class="table-wrap"><table>
  <tr><th>Data</th><th>Where</th><th>How to remove it</th></tr>
  <tr><td>Projects, sessions, page history, notes, board, theories and to-dos</td><td><code>~/Library/Application Support/Genboard/</code></td><td>Delete sessions or projects in the app, or delete that folder.</td></tr>
  <tr><td>Screenshots of pinned pages</td><td><code>~/Library/Application Support/Genboard/Screenshots/</code></td><td>Delete the session, or the folder.</td></tr>
  <tr><td>Website data from the built-in browser (cookies, so you stay signed in, and caches)</td><td><code>~/Library/WebKit/com.patlaplante.Genboard</code> and <code>~/Library/Caches/com.patlaplante.Genboard</code></td><td>Delete those folders while Genboard is closed.</td></tr>
  <tr><td>Your Anthropic API key</td><td>Your macOS Keychain</td><td><strong>Remove Key</strong> in Settings.</td></tr>
  <tr><td>Preferences, such as the models you chose</td><td><code>~/Library/Preferences/com.patlaplante.Genboard.plist</code></td><td>Delete the file.</td></tr>
  <tr><td>Backups you export (<code>.genboard</code> files)</td><td>Wherever you save them</td><td>Delete the file.</td></tr>
</table></div>
<p>This data is not synced or shared. Genealogy research often includes information about living people; it stays wherever you keep your Mac's files and backups.</p>

<h2>Websites you visit</h2>
<p>The built-in browser loads the websites you open, such as FamilySearch, WikiTree, Find a Grave and Généalogie Québec, the same way Safari would. Those sites receive what any browser sends them, and their own privacy policies apply. Genboard doesn't send them anything else.</p>

<h2>AI features (Claude)</h2>
<p>The AI features are off until you add your own Anthropic API key, and they send something only when you use them: when you ask the assistant a question, transcribe a record, ask for suggested cards, or draft a session summary. Each request goes directly from your Mac to Anthropic's API, with your key, and can include:</p>
<ul>
  <li>your question;</li>
  <li>the project's research context: its name, session goals and earlier summaries, to-dos, pinned pages with their notes, selected text and transcriptions, dead ends, and the cards, connections and theories on the board;</li>
  <li>the current page's text or a screenshot of it, if you choose to attach them;</li>
  <li>for transcription and suggested cards, the screenshot of that record.</li>
</ul>
<p>If you choose a local model for a task instead, that request goes only to the server address you set in Settings, normally a program on your own Mac, and nothing leaves the computer.</p>
<p>Anthropic processes these requests under its own <a href="https://www.anthropic.com/legal/commercial-terms">commercial terms</a> and <a href="https://www.anthropic.com/legal/privacy">privacy policy</a>, which apply to your API account. The developer never sees these requests or their answers.</p>

<h2>Updates</h2>
<p>Once a day, and when you choose <strong>Check for Updates…</strong>, Genboard downloads its update list from <code>patbonecrusher.github.io</code> and, when you agree to an update, the new version from GitHub. These requests carry what any download does, such as your IP address, and are handled under GitHub's privacy statement. Genboard doesn't send your system details or anything about your research. Updates use the open-source <a href="https://sparkle-project.org">Sparkle</a> framework, the only third-party code in the app.</p>

<h2>Third parties</h2>
<p>Apart from the websites you visit, GitHub for updates, and, if you use them, Anthropic's API, Genboard shares nothing with anyone.</p>

<h2>Children</h2>
<p>Genboard does not collect personal information from anyone, including children.</p>

<h2>Changes</h2>
<p>If Genboard's handling of information changes, this page will be updated before the release that changes it, and the effective date above will change.</p>

<h2>Contact</h2>
<p>Questions about this policy can be sent to the developer through <a href="{REPO}/issues">GitHub Issues</a>.</p>
""")

page("terms.html", "Terms of Service · Genboard",
     "The terms for using Genboard, a macOS research workbench for genealogy.",
     f"""
<h1>Terms of Service</h1>
<p class="meta">Effective {EFFECTIVE}</p>

<p>These terms apply to your use of the Genboard application for macOS ("Genboard"). By using Genboard you agree to them. If you do not agree, do not use Genboard.</p>

<h2>What Genboard is</h2>
<p>Genboard helps you organize genealogical research: it records the pages you visit, keeps your notes, and lets you lay out people, events, sources and theories. It is provided by an individual developer.</p>

<h2>Your research</h2>
<p>You are responsible for the conclusions you draw. Genboard's checks, family tree and AI features are aids, not proof: they can miss contradictions, misread records or suggest wrong connections. Verify facts against original records before relying on them or sharing them, and keep backups of anything important.</p>

<h2>Websites and records</h2>
<p>Genboard's browser shows third-party websites. Your use of those sites, and of the records and images they hold, is governed by their own terms. Do not use Genboard to copy or collect material in ways those terms forbid.</p>

<h2>AI features</h2>
<p>If you add an Anthropic API key, AI requests are sent to Anthropic under your own account and Anthropic's terms, and usage is billed to you by Anthropic. AI output can be wrong; review it before you rely on it. Nothing the AI suggests is added to your board until you choose to add it.</p>

<h2>Privacy and living people</h2>
<p>Be careful with information about living people, both in what you store and in what you share or export. The <a href="privacy.html">Privacy Policy</a> explains what Genboard stores and sends.</p>

<h2>No warranty</h2>
<p>Genboard is provided "as is" and "as available", without warranties of any kind, express or implied, including fitness for a particular purpose and non-infringement. The developer does not promise that Genboard will be error-free or that its checks, exports or AI features will be accurate.</p>

<h2>Limitation of liability</h2>
<p>To the fullest extent permitted by law, the developer is not liable for any indirect, incidental, special or consequential damages, or for any loss of data, arising from your use of Genboard.</p>

<h2>Changes</h2>
<p>These terms may be updated. The effective date above shows when they last changed. Continuing to use Genboard after a change means you accept the updated terms.</p>

<h2>Contact</h2>
<p>Questions about these terms can be sent to the developer through <a href="{REPO}/issues">GitHub Issues</a>.</p>
""")

print("Wrote", ", ".join(sorted(p.name for p in DOCS.glob("*.html"))))
