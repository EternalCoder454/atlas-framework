#!/usr/bin/env python3
"""Check the reference docs in docs/reference and build what the site reads.

    tools/docs.py [--root DIR] [--api FILE] check              fail on any broken page (CI runs this)
    tools/docs.py [--root DIR] [--api FILE] build <out dir>    check, then write the pages, the
                                                  images and index.json into
                                                  <out dir> (docs-published)

`check` also fails when a type or public member in api/atlas-ui.api is missing
from the atlas-ui pages: docs/reference is the single source for the API.
`--root` skips that check unless `--api FILE` names the API file too.

The AtlasOS site (atlasos.eterneon.net/framework) reads the docs-published branch.
docs/reference/README.md is the contract: the layout, the frontmatter and the
rules this script enforces. Only the standard library, so CI needs nothing
installed.
"""

import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "reference")  # `--root DIR` replaces it (the tests do)
CUSTOM_ROOT = False  # True when REF was given with --root
API = os.path.join(ROOT, "api", "atlas-ui.api")  # None: no API coverage check (`--root` without `--api`)
API_LIBRARY = "atlas-ui"  # the library whose pages describe that API

SLUG = re.compile(r"[a-z0-9]+(-[a-z0-9]+)*")
KEYS = {"title", "summary", "order", "since", "section", "deprecated"}
REQUIRED = ("title", "summary")
TEXT_KEYS = ("title", "summary", "section", "deprecated")
IMAGE_TYPES = (".png", ".webp", ".svg")
# What the site accepts: longer fields (in UTF-16 code units) or bigger files are skipped there.
LIMITS = {"title": 160, "summary": 400, "section": 60, "deprecated": 300, "since": 32}
LIBRARY_TITLE_LIMIT = 120
PAGE_BYTES = 512 * 1024
IMAGE_BYTES = 4 * 1024 * 1024
IMAGES_TOTAL_BYTES = 32 * 1024 * 1024
INDEX_BYTES = 1024 * 1024
MAX_DELIMITERS = 8000  # * _ ~ [ ] outside code: the site's parser is quadratic on them
MAX_PAGES = 500
MAX_LIBRARIES = 50
RESERVED = {"images", "index"}  # page and library slugs the site keeps for itself
DEFAULT_ORDER = 1000
MAX_ORDER = 1000000000
FENCE = re.compile(r"^( *)(`{3,}|~{3,})(.*)$")
MAX_LINE = 10000
LIST_ITEM = re.compile(r"^( {0,3})([-*+]|\d{1,9}[.)])( +|$)")
QUOTE = re.compile(r"^ {0,3}> ?")
# Control characters, line and paragraph separators and bidi controls: never in a title.
BAD_CHARS = re.compile("[\x00-\x1f\x7f-\x9f\u061c\u200b-\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufeff]")
# Any `<` that starts a tag, comment, declaration or processing instruction
# outside code: <b>, </div>, <img/src=x>, <!-- -->, <?php. Valid autolinks are
# blanked before this runs.
HTML = re.compile(r"<[A-Za-z/!?]")
AUTOLINK = re.compile(r"<([a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^\s<>]*|[^\s<>@]+@[^\s<>@]+)>")
# A backslash escape is matched first, so \` neither opens nor closes a span.
CODE_SPAN = re.compile(r"\\.|(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)", re.S)
TITLE = r"(?:\"[^\"]*\"|'[^']*'|\([^)]*\))"
LINK = re.compile(r"(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*<?([^)\s>]*)>?(?:\s+" + TITLE + r")?\s*\)")
REF_DEF = re.compile(r"^ *(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?\[([^\]^][^\]]*)\]:[ \t]*<?([^\s>]*)>?", re.M)
UNPARSED = re.compile(r"\]\(|!\[")
HEADING = re.compile(r"^ {0,3}(#{1,6})[ \t]+(.*?)(?:[ \t]+#+)?$")
SETEXT_H1 = re.compile(r"^ {0,3}=+[ \t]*$")
SETEXT_H2 = re.compile(r"^ {0,3}-{2,}[ \t]*$")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
SVG_HREF = re.compile(r"(?:xlink:)?href\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", re.I)


class Page:
    def __init__(self, path):
        self.path = path  # absolute
        self.rel = os.path.relpath(path, REF).replace(os.sep, "/")
        self.meta = {}
        self.body = []  # (line number, text)
        self.anchors = set()


class Library:
    def __init__(self, name):
        self.name = name
        self.pages = []
        self.images = []  # absolute paths of the validated image files


def u16(text):
    """Length in UTF-16 code units, which is what the site counts."""
    return len(text.encode("utf-16-le", "surrogatepass")) // 2


def fail(errors, page, line, message):
    where = f"docs/reference/{page.rel}" + (f":{line}" if line else "")
    errors.append(f"{where}: {message}")


def parse_scalar(raw):
    """A frontmatter value as text: quotes removed, nothing else interpreted."""
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        inner = raw[1:-1]
        return inner.replace('\\"', '"') if raw[0] == '"' else inner.replace("''", "'")
    return raw


def read_page(page, errors):
    try:
        if os.path.getsize(page.path) > PAGE_BYTES:
            fail(errors, page, 0, f"over {PAGE_BYTES // 1024} KiB: split the page")
            return
        with open(page.path, encoding="utf-8", newline="") as f:  # newline="": see any bare CR
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        fail(errors, page, 0, f"cannot read: {e}")
        return
    if re.search(r"\r(?!\n)", text):
        fail(errors, page, 0, "a bare CR (carriage return without a line feed): use LF or CRLF line ends")
        return
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        fail(errors, page, 1, "no frontmatter (the file must start with ---)")
        return
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        fail(errors, page, 1, "frontmatter is not closed with ---")
        return
    for i in range(1, end):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.fullmatch(r"([a-z]+):\s*(.*)", line)
        if not m:
            fail(errors, page, i + 1, "frontmatter lines must be `key: value` (one line each)")
            continue
        key, value = m.group(1), parse_scalar(m.group(2))
        if key not in KEYS:
            fail(errors, page, i + 1, f"unknown frontmatter key `{key}` (allowed: {', '.join(sorted(KEYS))})")
        elif key in page.meta:
            fail(errors, page, i + 1, f"`{key}` given twice")
        elif value == "" and key not in REQUIRED:
            fail(errors, page, i + 1, f"`{key}` is empty: give it a value or remove the line")
        else:
            page.meta[key] = value
    for key in REQUIRED:
        if not page.meta.get(key, "").strip():
            fail(errors, page, 0, f"missing `{key}`")
    for key, limit in LIMITS.items():
        if page.rel.endswith("/index.md") and key == "title":
            limit = LIBRARY_TITLE_LIMIT
        if u16(page.meta.get(key, "")) > limit:
            fail(errors, page, 0, f"`{key}` is longer than {limit} characters")
    for key in TEXT_KEYS:
        value = page.meta.get(key, "")
        if BAD_CHARS.search(value):
            fail(errors, page, 0, f"`{key}` has a control, line-separator or bidi character")
        if HTML.search(AUTOLINK.sub("", without_code(value))):
            fail(errors, page, 0, f"`{key}` has raw HTML (put it in backticks)")
    if "order" in page.meta:
        raw = page.meta["order"]
        if re.fullmatch(r"-?\d{1,12}(\.\d{1,9})?", raw, re.A) and abs(float(raw)) <= MAX_ORDER:
            page.meta["order"] = float(raw) if "." in raw else int(raw)
        else:
            fail(errors, page, 0, f"`order` must be a number between -{MAX_ORDER} and {MAX_ORDER}")
            del page.meta["order"]
    if "since" in page.meta and not re.fullmatch(r"\d+\.\d+\.\d+", page.meta["since"], re.A):
        fail(errors, page, 0, "`since` must be a version like 1.4.0")
    page.body = [(i + 1, lines[i]) for i in range(end + 1, len(lines))]


def github_slug(text):
    """The anchor GitHub gives a heading: lowercase, punctuation dropped,
    spaces to hyphens. Markup is removed first, as the rendered text has none."""
    text = LINK.sub(lambda m: m.group(2), text)
    text = CODE_SPAN.sub(lambda m: m.group(2) if m.group(1) else m.group(0), text)
    text = re.sub(r"[*~]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def split_quotes(line, limit=None):
    """(depth, rest): the blockquote markers removed (at most `limit`)."""
    depth = 0
    while limit is None or depth < limit:
        m = QUOTE.match(line)
        if not m:
            break
        line = line[m.end():]
        depth += 1
    return depth, line


def blank(text):
    """The text with everything but newlines replaced by spaces: offsets stay."""
    return re.sub(r"[^\n]", " ", text)


def without_code(text):
    return CODE_SPAN.sub(lambda m: blank(m.group(0)) if m.group(1) else m.group(0), text)


def scan_body(page, errors):
    """Fences, raw HTML, H1s and anchors. Returns the paragraphs outside code
    as (first line number, text with newlines)."""
    paragraphs = []
    para = []
    para_is_item = False
    fence = None  # (marker, indent, quote depth, inside a list)
    seen = {}
    prev_blank = True
    in_list = False

    def flush():
        nonlocal para_is_item
        if para:
            paragraphs.append((para[0][0], "\n".join(t for _, t in para)))
            para.clear()
        para_is_item = False

    def add_anchor(text):
        base = github_slug(text)
        n = seen.get(base, 0)
        candidate = base
        while candidate in page.anchors:  # GitHub: keep counting until the name is free
            n += 1
            candidate = f"{base}-{n}"
        seen[base] = n
        page.anchors.add(candidate)

    for number, raw in page.body:
        if len(raw) > MAX_LINE:
            fail(errors, page, number, f"line over {MAX_LINE} characters")
            continue
        raw = raw.expandtabs(4)
        depth, _ = split_quotes(raw)
        if fence:
            marker, f_indent, f_depth, f_list = fence
            _, content = split_quotes(raw, f_depth)
            ended = depth < f_depth or (f_list and content.strip() and len(content) - len(content.lstrip(" ")) < f_indent)
            if ended:  # the quote or list item that held the fence is over
                fence = None
                fail(errors, page, 0, "a code fence is never closed")
            else:
                m = FENCE.match(content)
                if m and m.group(2)[0] == marker[0] and len(m.group(2)) >= len(marker) \
                        and not m.group(3).strip() and len(m.group(1)) - f_indent <= 3:
                    fence = None
                    prev_blank = True
                continue
        line = split_quotes(raw)[1]
        m = FENCE.match(line)
        indent = len(line) - len(line.lstrip(" "))
        item = LIST_ITEM.match(line)
        if not m and item:  # a fence can open on a list item's own line
            m = FENCE.match(" " * item.end() + line[item.end():])
        if m and (len(m.group(1)) <= 3 or in_list or item) and not (m.group(2)[0] == "`" and "`" in m.group(3)):
            flush()
            fence = (m.group(2), len(m.group(1)), depth, bool(in_list or item))
            if not m.group(3).strip():
                fail(errors, page, number, "code fence without a language (```qml, ```rust, ```sh, ```text ...)")
            if item:
                in_list = True
            continue
        if not line.strip():
            flush()
            prev_blank = True
            continue
        if indent >= 4 and prev_blank and not in_list:
            flush()
            fail(errors, page, number, "indented code block: use a fence with a language")
            continue
        if para and not prev_blank and not para_is_item:
            if SETEXT_H1.match(line):
                fail(errors, page, number, "`#` heading: the title comes from frontmatter, start at ##")
                add_anchor(" ".join(t.strip() for _, t in para))
                flush()
                continue
            if SETEXT_H2.match(line):
                add_anchor(" ".join(t.strip() for _, t in para))
                flush()
                continue
        h = HEADING.match(line.rstrip())
        if item:
            in_list = True
        elif indent <= 1 and (prev_blank or h):
            in_list = False
        prev_blank = False
        if h:
            flush()
            if len(h.group(1)) == 1:
                fail(errors, page, number, "`#` heading: the title comes from frontmatter, start at ##")
            add_anchor(h.group(2))
            para.append((number, line))
            flush()
            continue
        if item or "|" in line:  # a list item or a table row is its own block
            flush()
            para_is_item = bool(item)
            para.append((number, line))
            if "|" in line and not item:
                flush()
            continue
        para.append((number, line))
    flush()
    if fence:
        fail(errors, page, 0, "a code fence is never closed")
    delimiters = sum(len(re.findall(r"[*_~\[\]]", text)) for _, text in paragraphs)
    if delimiters > MAX_DELIMITERS:
        fail(errors, page, 0, f"{delimiters} of * _ ~ [ ] outside code (the site renders at most {MAX_DELIMITERS}): split the page")
        return []
    for start, text in paragraphs:
        cleaned = AUTOLINK.sub(lambda m: blank(m.group(0)), without_code(text))
        found = HTML.search(cleaned)
        if found:
            fail(errors, page, start + cleaned.count("\n", 0, found.start()),
                 "raw HTML (the site removes it; put it in backticks or use Markdown)")
    return paragraphs


def scan_links(text, offset, found, unparsed):
    """Every inline link and image in text, nested ones too. found gets
    (offset, match); unparsed gets the offsets of `](` and `![` that no link
    consumed."""
    for m in LINK.finditer(text):
        found.append((offset + m.start(), m))
        scan_links(m.group(2), offset + m.start(2), found, unparsed)
    rest = LINK.sub(lambda m: blank(m.group(0)), text)
    unparsed.extend(offset + m.start() for m in UNPARSED.finditer(rest))


def check_target(page, number, target, image, pages_by_path, images, errors):
    library_dir = page.rel.split("/")[0] if "/" in page.rel else "<library>"
    if SCHEME.match(target):
        if target.startswith("http://"):
            fail(errors, page, number, f"plain http link: {target} (use https)")
        elif image:
            fail(errors, page, number, f"remote image: {target} (put it in {library_dir}/images/)")
        elif not re.match(r"^(https|mailto):", target):
            fail(errors, page, number, f"link scheme not allowed: {target}")
        return
    path, _, anchor = target.partition("#")
    path, anchor = urllib.parse.unquote(path), urllib.parse.unquote(anchor)
    if BAD_CHARS.search(path + anchor) or "\\" in path:
        fail(errors, page, number, f"link with a control or backslash character: {target!r}")
        return
    if path.startswith("/"):
        fail(errors, page, number, f"absolute link: {target} (link to the .md file relatively)")
        return
    resolved = os.path.normpath(os.path.join(os.path.dirname(page.path), path)) if path else page.path
    if not resolved.startswith(REF + os.sep):
        fail(errors, page, number, f"link leaves docs/reference: {target}")
        return
    if image:
        rel = os.path.relpath(resolved, REF).split(os.sep)
        if resolved not in images:
            if os.path.lexists(resolved):
                fail(errors, page, number, f"not a valid image file: {target}")
            else:
                fail(errors, page, number, f"missing image: {target}")
        elif len(rel) != 3 or rel[1] != "images":
            fail(errors, page, number, f"images live in <library>/images/ as PNG, WebP or SVG: {target}")
        return
    target_page = pages_by_path.get(resolved)
    if target_page is None:
        fail(errors, page, number, f"link to a page that does not exist: {target}")
    elif anchor and anchor not in target_page.anchors:
        fail(errors, page, number, f"no heading `#{anchor}` in {target_page.rel}")


def check_links(page, paragraphs, pages_by_path, images, errors):
    for start, text in paragraphs:
        cleaned = without_code(text)

        def line_of(offset):
            return start + cleaned.count("\n", 0, offset)

        for m in AUTOLINK.finditer(cleaned):
            inner = m.group(1)
            if SCHEME.match(inner):
                if inner.startswith("http://"):
                    fail(errors, page, line_of(m.start()), f"plain http link: {inner} (use https)")
                elif not re.match(r"^(https|mailto):", inner):
                    fail(errors, page, line_of(m.start()), f"link scheme not allowed: {inner}")
        cleaned = AUTOLINK.sub(lambda m: blank(m.group(0)), cleaned)
        for m in REF_DEF.finditer(cleaned):
            check_target(page, line_of(m.start()), m.group(2), False, pages_by_path, images, errors)
        found, unparsed = [], []
        scan_links(cleaned, 0, found, unparsed)
        for offset, m in found:
            image, alt, target = m.group(1) == "!", m.group(2).strip(), m.group(3)
            number = line_of(offset)
            if image and not alt:
                fail(errors, page, number, f"image without alt text: {target}")
            check_target(page, number, target, image, pages_by_path, images, errors)
        for offset in unparsed:
            fail(errors, page, line_of(offset), "link the checker can't parse (spaces or brackets in the address?): write it plainly")


def check_svg(data, errors, name):
    """An SVG is an image, not a program: no script, no external reference,
    no DTD, no animation, no CSS that loads anything."""
    if data[:2] in (b"\xff\xfe", b"\xfe\xff") or b"\0" in data:
        errors.append(f"{name}: an SVG must be UTF-8 (this one looks like UTF-16 or has NUL bytes)")
        return
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        errors.append(f"{name}: an SVG must be valid UTF-8")
        return
    low = text.lower()
    if "<script" in low or "<foreignobject" in low or re.search(r"[\s\"'/]on\w+\s*=", low):
        errors.append(f"{name}: an SVG must not hold scripts, event handlers or foreignObject")
    if "<!doctype" in low or "<!entity" in low:
        errors.append(f"{name}: an SVG must not have a DOCTYPE or entities")
    if re.search(r"<\s*/?\s*[a-z_][\w.-]*:", low):
        errors.append(f"{name}: an SVG must not use prefixed element names (<x:script>)")
    if re.search(r"<\s*(set\b|animate)", low):
        errors.append(f"{name}: an SVG must not use <set> or <animate*>")
    styles = [m.group(1) for m in re.finditer(r"<style\b[^>]*>(.*?)</style\s*>", low, re.S)]
    styles += [m.group(1) or m.group(2) for m in re.finditer(r"\bstyle\s*=\s*(?:\"([^\"]*)\"|'([^']*)')", low)]
    if "@import" in low or any("url(" in st or "\\" in st for st in styles):
        errors.append(f"{name}: an SVG's CSS must not use url(), @import or escapes")
    for h in SVG_HREF.finditer(text):
        if not next(g for g in h.groups() if g is not None).strip().startswith("#"):
            errors.append(f"{name}: an SVG may only link to #anchors inside itself")
            break


def check_image(path, errors, name):
    """The file really is what its extension says, and an SVG runs nothing."""
    try:
        size = os.path.getsize(path)
        if size > IMAGE_BYTES:
            errors.append(f"{name}: over {IMAGE_BYTES // 1048576} MiB")
            return size
        with open(path, "rb") as f:
            data = f.read()
    except OSError as e:
        errors.append(f"{name}: cannot read: {e}")
        return 0
    ext = os.path.splitext(path)[1].lower()
    if ext == ".png" and not data.startswith(PNG_MAGIC):
        errors.append(f"{name}: not a PNG file")
    elif ext == ".webp" and not (data[:4] == b"RIFF" and data[8:12] == b"WEBP"):
        errors.append(f"{name}: not a WebP file")
    elif ext == ".svg":
        check_svg(data, errors, name)
    return size


def collect(errors):
    """Returns (overview, libraries). Every symlink is an error, and every
    path must stay under the real docs/reference."""
    if not os.path.isdir(REF):
        errors.append("docs/reference does not exist")
        return None, []
    real_ref = os.path.realpath(REF)
    if not CUSTOM_ROOT:  # REF and every folder between it and the repo root
        here = REF
        while here != ROOT and here != os.path.dirname(here):
            if os.path.islink(here):
                errors.append(f"{os.path.relpath(here, ROOT)}: symbolic links are not allowed")
                return None, []
            here = os.path.dirname(here)

    def safe(path, label):
        if os.path.islink(path):
            errors.append(f"{label}: symbolic links are not allowed")
            return False
        if not (os.path.realpath(path) + os.sep).startswith(real_ref + os.sep):
            errors.append(f"{label}: leaves docs/reference")
            return False
        return True

    overview = None
    libraries = []
    total_images = 0
    for name in sorted(os.listdir(REF)):
        full = os.path.join(REF, name)
        if not safe(full, f"docs/reference/{name}"):
            continue
        if os.path.isfile(full):
            if name == "index.md":
                overview = Page(full)
            elif name != "README.md":
                errors.append(f"docs/reference/{name}: only index.md and README.md go at the top; pages go in a library folder")
            continue
        if not SLUG.fullmatch(name) or name in RESERVED:
            errors.append(f"docs/reference/{name}: a library folder name must be lowercase-with-hyphens, not images or index")
            continue
        lib = Library(name)
        for entry in sorted(os.listdir(full)):
            path = os.path.join(full, entry)
            label = f"docs/reference/{name}/{entry}"
            if not safe(path, label):
                continue
            if entry == "images" and os.path.isdir(path):
                for img in sorted(os.listdir(path)):
                    img_path = os.path.join(path, img)
                    img_label = f"{label}/{img}"
                    if not safe(img_path, img_label):
                        continue
                    if not img.lower().endswith(IMAGE_TYPES) or not os.path.isfile(img_path):
                        errors.append(f"{img_label}: only PNG, WebP and SVG files")
                        continue
                    before = len(errors)
                    total_images += check_image(img_path, errors, img_label)
                    if len(errors) == before:
                        lib.images.append(img_path)
                continue
            if not entry.endswith(".md") or not os.path.isfile(path):
                errors.append(f"{label}: only .md pages and an images/ folder")
                continue
            if entry == "images.md":
                errors.append(f"{label}: `images` is reserved, pick another name")
                continue
            if not SLUG.fullmatch(entry[:-3]):
                errors.append(f"{label}: a page name must be lowercase-with-hyphens")
                continue
            lib.pages.append(Page(path))
        if not any(p.rel.endswith("/index.md") for p in lib.pages):
            errors.append(f"docs/reference/{name}: no index.md (the library's overview)")
        libraries.append(lib)
    if total_images > IMAGES_TOTAL_BYTES:
        errors.append(f"docs/reference: images add up to {total_images // 1048576} MiB (at most {IMAGES_TOTAL_BYTES // 1048576})")
    return overview, libraries


def check():
    """Returns (overview, libraries, errors)."""
    errors = []
    overview, libraries = collect(errors)
    every = ([overview] if overview else []) + [p for lib in libraries for p in lib.pages]
    if len(libraries) > MAX_LIBRARIES:
        errors.append(f"docs/reference: {len(libraries)} libraries (the site takes at most {MAX_LIBRARIES})")
    if len(every) > MAX_PAGES:
        errors.append(f"docs/reference: {len(every)} pages (the site takes at most {MAX_PAGES})")
    for page in every:
        read_page(page, errors)
    prose = {page.path: scan_body(page, errors) for page in every}
    by_path = {page.path: page for page in every}
    images = {path for lib in libraries for path in lib.images}
    for page in every:
        check_links(page, prose[page.path], by_path, images, errors)
    if API:
        check_api_coverage(libraries, errors)
    return overview, libraries, errors


def page_slug(type_name):
    """AtlasButton -> atlas-button, DataTable -> data-table."""
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", "-", type_name).lower()


def read_api(errors):
    """{type: set of public member names} from the apidump file; enum values
    count as members. Members starting with _ are private."""
    types = {}
    try:
        with open(API, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        errors.append(f"{API}: cannot read the API file ({e})")
        return types
    for number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        m = re.fullmatch(r"(\w+)\.type", line)
        if m:
            types.setdefault(m.group(1), set())
            continue
        m = re.match(r"(\w+)\.(property|signal|method) (\w+)", line)
        if m:
            name = m.group(3)
        else:
            m = re.match(r"(\w+)\.enum \w+: (\w+)", line)
            name = m.group(2) if m else None
        if not m:
            errors.append(f"{os.path.basename(API)}:{number}: unrecognised line")
            continue
        if not name.startswith("_"):
            types.setdefault(m.group(1), set()).add(name)
    return types


NAME_SPAN = re.compile(r"(?:\w+\.)*(\w+)")


def documented_names(page):
    """Names a page puts in backticks: `name`, `name(` or `Type.name`, outside
    code fences. A signal's `onName` handler counts for the signal."""
    names = set()
    fenced = False
    for _, text in page.body:
        if FENCE.match(text):
            fenced = not fenced
            continue
        if fenced:
            continue
        for span in CODE_SPAN.finditer(text):
            if span.group(1) is None:
                continue
            m = NAME_SPAN.match(span.group(2).strip())
            if m:
                name = m.group(1)
                names.add(name)
                if name.startswith("on") and len(name) > 2 and name[2].isupper():
                    names.add(name[2].lower() + name[3:])
    return names


def check_api_coverage(libraries, errors):
    """Every API type has a page and every public member is on it, or on the
    page of a type it links to that has the member (an inherited one)."""
    lib = next((l for l in libraries if l.name == API_LIBRARY), None)
    if lib is None:
        errors.append(f"{API_LIBRARY}: no such library, but the API file lists types")
        return
    api = read_api(errors)
    pages = {os.path.basename(p.path)[:-3]: p for p in lib.pages}
    cache = {}

    def names(page):
        if page.path not in cache:
            cache[page.path] = documented_names(page)
        return cache[page.path]

    for type_name in sorted(api):
        slug = page_slug(type_name)
        page = pages.get(slug)
        if page is None:
            errors.append(f"{API_LIBRARY}/{slug}.md: no page for {type_name} (api/{os.path.basename(API)})")
            continue
        linked = set()
        for _, text in page.body:
            for m in LINK.finditer(without_code(text)):
                target = m.group(3).split("#")[0]
                if target.endswith(".md") and "/" not in target and target[:-3] in pages:
                    linked.add(target[:-3])
        bases = [t for t in api if page_slug(t) in linked and t != type_name]
        mine = names(page)
        for member in sorted(api[type_name]):
            if member in mine:
                continue
            if any(member in api[t] and member in names(pages[page_slug(t)]) for t in bases):
                continue
            errors.append(f"{page.rel}: `{member}` of {type_name} is not documented (add it, or link the base type's page that has it)")


def git(*args):
    """Git's output; any failure stops the build."""
    try:
        done = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, check=False, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        sys.exit(f"docs: git {' '.join(args)} failed: {e}")
    if done.returncode != 0:
        sys.exit(f"docs: git {' '.join(args)} failed: {done.stderr.strip()}")
    return done.stdout.strip()


def project_version():
    with open(os.path.join(ROOT, "CMakeLists.txt"), encoding="utf-8") as f:
        m = re.search(r"project\(\s*atlas-framework\s+VERSION\s+([0-9.]+)", f.read())
    if not m:
        sys.exit("docs: no project version in CMakeLists.txt")
    return m.group(1)


def page_entry(page):
    entry = {
        "slug": os.path.basename(page.rel)[:-3],
        "title": str(page.meta["title"]),
        "summary": str(page.meta["summary"]),
        "path": page.rel,
        "source": f"docs/reference/{page.rel}",
    }
    entry["order"] = page.meta.get("order", DEFAULT_ORDER)
    for key in ("since", "section", "deprecated"):
        if key in page.meta:
            entry[key] = str(page.meta[key])
    return entry


def sort_key(entry):
    return (entry["order"], entry["title"].lower())


def build(out, overview, libraries):
    """Writes into a temporary sibling directory, then renames it into place:
    a failure leaves no half-written out directory. Only the validated files
    are copied."""
    if os.path.lexists(out):
        if not os.path.isdir(out) or os.path.islink(out) or os.listdir(out):
            sys.exit(f"docs: {out} must be a new or empty directory")
    version = project_version()
    commit = git("rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        sys.exit(f"docs: git gave no commit id ({commit!r})")
    released = git("tag", "--points-at", "HEAD", "--list", f"v{version}") == f"v{version}"
    index = {
        "version": version,
        "released": released,
        "commit": commit,
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "libraries": [],
    }
    parent = os.path.dirname(out)
    os.makedirs(parent, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=os.path.basename(out) + ".tmp-", dir=parent)
    try:
        if overview:
            index["overview"] = page_entry(overview)
            shutil.copyfile(overview.path, os.path.join(tmp, "index.md"))
        for lib in libraries:
            lib_index = next(p for p in lib.pages if p.rel == f"{lib.name}/index.md")
            index["libraries"].append({
                "slug": lib.name,
                "title": str(lib_index.meta["title"]),
                "summary": str(lib_index.meta["summary"]),
                "order": lib_index.meta.get("order", DEFAULT_ORDER),
                "pages": sorted((page_entry(p) for p in lib.pages), key=sort_key),
            })
            os.makedirs(os.path.join(tmp, lib.name))
            for p in lib.pages:
                shutil.copyfile(p.path, os.path.join(tmp, p.rel))
            if lib.images:
                os.makedirs(os.path.join(tmp, lib.name, "images"))
                for img in lib.images:
                    shutil.copyfile(img, os.path.join(tmp, lib.name, "images", os.path.basename(img)))
        index["libraries"].sort(key=sort_key)
        data = json.dumps(index, indent=1, ensure_ascii=False, allow_nan=False) + "\n"
        if len(data.encode("utf-8")) > INDEX_BYTES:
            sys.exit(f"docs: index.json is over {INDEX_BYTES // 1024} KiB, which the site refuses")
        with open(os.path.join(tmp, "index.json"), "w", encoding="utf-8") as f:
            f.write(data)
        os.chmod(tmp, 0o755)
        os.rename(tmp, out)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    count = sum(len(lib.pages) for lib in libraries)
    print(f"docs: {count} pages in {len(libraries)} libraries written to {out}")


def main(argv):
    global REF, CUSTOM_ROOT, API
    argv = list(argv)
    if "--root" in argv:  # the reference folder to check (the tests use it)
        i = argv.index("--root")
        if i + 1 >= len(argv):
            sys.exit(__doc__.strip().split("\n\n")[1])
        REF = os.path.abspath(argv[i + 1])
        CUSTOM_ROOT = True
        del argv[i:i + 2]
        API = None
    if "--api" in argv:  # the API file to check coverage of (default: api/atlas-ui.api, none with --root)
        i = argv.index("--api")
        if i + 1 >= len(argv):
            sys.exit(__doc__.strip().split("\n\n")[1])
        API = os.path.abspath(argv[i + 1])
        del argv[i:i + 2]
    if len(argv) < 2 or argv[1] not in ("check", "build") or (argv[1] == "build") != (len(argv) == 3):
        sys.exit(__doc__.strip().split("\n\n")[1])
    overview, libraries, errors = check()
    if argv[1] == "build" and not libraries:
        errors.append("docs/reference: no libraries to publish")
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(f"docs: {len(errors)} problem(s)")
    if argv[1] == "check":
        print(f"docs: ok ({sum(len(lib.pages) for lib in libraries)} pages in {len(libraries)} libraries)")
    else:
        build(os.path.abspath(argv[2]), overview, libraries)


if __name__ == "__main__":
    main(sys.argv)
