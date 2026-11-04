#!/usr/bin/env python3
"""Adds a release to docs/appcast.xml, the Sparkle feed the app checks for updates.

    tools/appcast.py --version 0.2 --build 3 --url https://…/Genboard-0.2.zip \
        --signature 'sparkle:edSignature="…" length="…"' --notes RELEASE_NOTES.md
"""
import argparse
import email.utils
import html
import pathlib
import re
import sys

APPCAST = pathlib.Path(__file__).resolve().parent.parent / "docs" / "appcast.xml"
HEADER = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Genboard</title>
    <link>https://patbonecrusher.github.io/genboard/appcast.xml</link>
    <description>Genboard updates</description>
    <language>en</language>
  </channel>
</rss>
"""


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    return re.sub(r"(?<!\*)\*(?!\s)(.+?)(?<!\s)\*", r"<em>\1</em>", text)


def notes_html(markdown: str) -> str:
    """The small Markdown subset release notes use: paragraphs, bullets, bold, italics, code."""
    out, items = [], []
    lines = markdown.strip().splitlines()
    if lines and not lines[0].startswith(("-", "*")):
        lines = lines[1:]  # the "Genboard 0.2" title line; Sparkle shows the version already
    for line in lines + [""]:
        if line.startswith("- "):
            items.append(f"<li>{inline(line[2:])}</li>")
            continue
        if items:
            out.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if line.strip():
            out.append(f"<p>{inline(line.strip())}</p>")
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--signature", required=True, help="sign_update output")
    parser.add_argument("--notes", required=True)
    parser.add_argument("--minimum-system", default="15.0")
    parser.add_argument("--appcast", default=str(APPCAST))
    args = parser.parse_args()

    if not re.fullmatch(r'sparkle:edSignature="[^"]+" length="\d+"', args.signature.strip()):
        sys.exit(f"error: unexpected sign_update output: {args.signature!r}")
    path = pathlib.Path(args.appcast)
    feed = path.read_text(encoding="utf-8") if path.exists() else HEADER
    if f"<sparkle:version>{args.build}</sparkle:version>" in feed:
        sys.exit(f"error: build {args.build} is already in {path.name}; bump CURRENT_PROJECT_VERSION")

    item = f"""    <item>
      <title>Genboard {html.escape(args.version)}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{html.escape(args.build)}</sparkle:version>
      <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{html.escape(args.minimum_system)}</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes_html(pathlib.Path(args.notes).read_text(encoding="utf-8"))}
      ]]></description>
      <enclosure url="{html.escape(args.url)}" type="application/octet-stream" {args.signature.strip()}/>
    </item>
"""
    # Newest first, right after the channel's own fields.
    anchor = "    <language>en</language>\n"
    if anchor not in feed:
        sys.exit(f"error: {path.name} doesn't look like a Genboard appcast")
    path.write_text(feed.replace(anchor, anchor + item, 1), encoding="utf-8")
    print(f"Added Genboard {args.version} (build {args.build}) to {path}")


if __name__ == "__main__":
    main()
