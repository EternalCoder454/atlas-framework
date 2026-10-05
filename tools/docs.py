#!/usr/bin/env python3
"""Check the reference docs in docs/reference and build what the site reads.

    tools/docs.py check              fail on any broken page (CI runs this)
    tools/docs.py build <out dir>    check, then write the pages, the images
                                     and index.json into <out dir> (the
                                     docs-published branch)

The AtlasOS site (atlasos.eterneon.net/docs) reads the docs-published branch.
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "reference")

SLUG = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KEYS = {"title", "summary", "order", "since", "section", "deprecated"}
REQUIRED = ("title", "summary")
IMAGE_TYPES = (".png", ".webp", ".svg")
# What the site accepts: longer fields or bigger files are skipped there.
LIMITS = {"title": 160, "summary": 400, "section": 60, "deprecated": 300, "since": 32}
LIBRARY_TITLE_LIMIT = 120
PAGE_BYTES = 512 * 1024
IMAGE_BYTES = 4 * 1024 * 1024
INDEX_BYTES = 1024 * 1024
MAX_DELIMITERS = 8000  # * _ ~ [ ] outside code: the site's parser is quadratic on them
MAX_PAGES = 500
MAX_LIBRARIES = 50
RESERVED = {"images", "index"}  # page and library slugs the site keeps for itself
DEFAULT_ORDER = 1000
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
# A tag or comment outside code: <b>, </div>, <br/>, <!-- -->. An autolink
# (<https://...>, <me@example.org>) is not HTML.
HTML = re.compile(r"<(/?[A-Za-z][A-Za-z0-9-]*(\s[^<>]*)?/?)>|<!--")
AUTOLINK = re.compile(r"<([a-zA-Z][a-zA-Z0-9+.-]{1,31}:[^\s<>]*|[^\s<>@]+@[^\s<>@]+)>")
CODE_SPAN = re.compile(r"(`+)(.+?)\1")
LINK = re.compile(r"(!?)\[((?:[^\[\]]|\[[^\]]*\])*)\]\(\s*<?([^)\s>]*)>?(?:\s+\"[^\"]*\")?\s*\)")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$")


class Page:
    def __init__(self, path):
        self.path = path  # absolute
        self.rel = os.path.relpath(path, REF).replace(os.sep, "/")
        self.meta = {}
        self.body = []  # (line number, text)
        self.anchors = set()


def fail(errors, page, line, message):
    where = f"docs/reference/{page.rel}" + (f":{line}" if line else "")
    errors.append(f"{where}: {message}")


def parse_scalar(raw):
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] and raw[0] in "\"'":
        inner = raw[1:-1]
        return inner.replace('\\"', '"') if raw[0] == '"' else inner.replace("''", "'")
    if re.fullmatch(r"-?\d+(\.\d+)?", raw):
        return float(raw) if "." in raw else int(raw)
    return raw


def read_page(page, errors):
    try:
        if os.path.getsize(page.path) > PAGE_BYTES:
            fail(errors, page, 0, f"over {PAGE_BYTES // 1024} KiB: split the page")
            return
        with open(page.path, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except (OSError, UnicodeDecodeError) as e:
        fail(errors, page, 0, f"cannot read: {e}")
        return
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
        else:
            page.meta[key] = value
    for key in REQUIRED:
        if not str(page.meta.get(key, "")).strip():
            fail(errors, page, 0, f"missing `{key}`")
    for key, limit in LIMITS.items():
        if page.rel.endswith("/index.md") and key == "title":
            limit = LIBRARY_TITLE_LIMIT
        if len(str(page.meta.get(key, ""))) > limit:
            fail(errors, page, 0, f"`{key}` is longer than {limit} characters")
    if "order" in page.meta and not isinstance(page.meta["order"], (int, float)):
        fail(errors, page, 0, "`order` must be a number")
    if "since" in page.meta and not re.fullmatch(r"\d+\.\d+\.\d+", str(page.meta["since"])):
        fail(errors, page, 0, "`since` must be a version like 1.4.0")
    page.body = [(i + 1, lines[i]) for i in range(end + 1, len(lines))]


def github_slug(text):
    """The anchor GitHub gives a heading: lowercase, punctuation dropped,
    spaces to hyphens. Markup is removed first, as the rendered text has none."""
    text = LINK.sub(lambda m: m.group(2), text)
    text = CODE_SPAN.sub(lambda m: m.group(2), text)
    text = re.sub(r"[*~]", "", text).strip().lower()
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def scan_body(page, errors):
    """Fences, raw HTML, H1s and anchors. Returns the lines outside code."""
    prose = []
    fence = None
    seen = {}
    for number, line in page.body:
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m:
            fence = m.group(1)
            info = m.group(2).strip()
            if not info:
                fail(errors, page, number, "code fence without a language (```qml, ```rust, ```sh, ```text ...)")
            continue
        if line.startswith("    ") and (not prose or not prose[-1][1].strip()):
            fail(errors, page, number, "indented code block: use a fence with a language")
            continue
        prose.append((number, line))
        h = HEADING.match(line)
        if h:
            if len(h.group(1)) == 1:
                fail(errors, page, number, "`#` heading: the title comes from frontmatter, start at ##")
            base = github_slug(h.group(2))
            n = seen.get(base, 0)
            seen[base] = n + 1
            page.anchors.add(base if n == 0 else f"{base}-{n}")
        text = CODE_SPAN.sub("", AUTOLINK.sub("", line))
        if HTML.search(text):
            fail(errors, page, number, "raw HTML (the site removes it; use Markdown)")
    if fence:
        fail(errors, page, 0, "a code fence is never closed")
    delimiters = sum(len(re.findall(r"[*_~\[\]]", line)) for _, line in prose)
    if delimiters > MAX_DELIMITERS:
        fail(errors, page, 0, f"{delimiters} of * _ ~ [ ] outside code (the site renders at most {MAX_DELIMITERS}): split the page")
    return prose


def check_links(page, prose, pages_by_path, errors):
    library_dir = page.rel.split("/")[0] if "/" in page.rel else None
    for number, line in prose:
        for m in LINK.finditer(CODE_SPAN.sub("", line)):
            image, alt, target = m.group(1) == "!", m.group(2).strip(), m.group(3)
            if image and not alt:
                fail(errors, page, number, f"image without alt text: {target}")
            if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
                if target.startswith("http://"):
                    fail(errors, page, number, f"plain http link: {target} (use https)")
                elif not image and not re.match(r"^(https|mailto):", target):
                    fail(errors, page, number, f"link scheme not allowed: {target}")
                elif image:
                    fail(errors, page, number, f"remote image: {target} (put it in {library_dir}/images/)")
                continue
            path, _, anchor = target.partition("#")
            if path.startswith("/"):
                fail(errors, page, number, f"absolute link: {target} (link to the .md file relatively)")
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(page.path), path)) if path else page.path
            if not resolved.startswith(REF + os.sep):
                fail(errors, page, number, f"link leaves docs/reference: {target}")
                continue
            if image:
                rel = os.path.relpath(resolved, REF).split(os.sep)
                if not os.path.isfile(resolved):
                    fail(errors, page, number, f"missing image: {target}")
                elif len(rel) != 3 or rel[1] != "images" or not resolved.lower().endswith(IMAGE_TYPES):
                    fail(errors, page, number, f"images live in <library>/images/ as PNG, WebP or SVG: {target}")
                continue
            target_page = pages_by_path.get(resolved)
            if target_page is None:
                fail(errors, page, number, f"link to a page that does not exist: {target}")
            elif anchor and anchor not in target_page.anchors:
                fail(errors, page, number, f"no heading `#{anchor}` in {target_page.rel}")


def collect(errors):
    if not os.path.isdir(REF):
        errors.append("docs/reference does not exist")
        return None, []
    overview = None
    libraries = []
    for name in sorted(os.listdir(REF)):
        full = os.path.join(REF, name)
        if os.path.isfile(full):
            if name == "index.md":
                overview = Page(full)
            elif name != "README.md":
                errors.append(f"docs/reference/{name}: only index.md and README.md go at the top; pages go in a library folder")
            continue
        if not SLUG.match(name) or name in RESERVED:
            errors.append(f"docs/reference/{name}: a library folder name must be lowercase-with-hyphens, not images or index")
            continue
        pages = []
        for entry in sorted(os.listdir(full)):
            path = os.path.join(full, entry)
            if entry == "images" and os.path.isdir(path):
                for img in sorted(os.listdir(path)):
                    img_path = os.path.join(path, img)
                    if not img.lower().endswith(IMAGE_TYPES) or not os.path.isfile(img_path):
                        errors.append(f"docs/reference/{name}/images/{img}: only PNG, WebP and SVG files")
                    elif os.path.getsize(img_path) > IMAGE_BYTES:
                        errors.append(f"docs/reference/{name}/images/{img}: over {IMAGE_BYTES // 1048576} MiB")
                continue
            if not entry.endswith(".md") or not os.path.isfile(path):
                errors.append(f"docs/reference/{name}/{entry}: only .md pages and an images/ folder")
                continue
            if entry == "images.md":
                errors.append(f"docs/reference/{name}/images.md: `images` is reserved, pick another name")
                continue
            if not SLUG.match(entry[:-3]):
                errors.append(f"docs/reference/{name}/{entry}: a page name must be lowercase-with-hyphens")
                continue
            pages.append(Page(path))
        if not any(p.rel.endswith("/index.md") for p in pages):
            errors.append(f"docs/reference/{name}: no index.md (the library's overview)")
        libraries.append((name, pages))
    return overview, libraries


def check():
    """Returns (overview, libraries, errors)."""
    errors = []
    overview, libraries = collect(errors)
    every = ([overview] if overview else []) + [p for _, pages in libraries for p in pages]
    if len(libraries) > MAX_LIBRARIES:
        errors.append(f"docs/reference: {len(libraries)} libraries (the site takes at most {MAX_LIBRARIES})")
    page_count = sum(len(pages) for _, pages in libraries)
    if page_count > MAX_PAGES:
        errors.append(f"docs/reference: {page_count} pages (the site takes at most {MAX_PAGES})")
    for page in every:
        read_page(page, errors)
    prose = {page.path: scan_body(page, errors) for page in every}
    by_path = {page.path: page for page in every}
    for page in every:
        check_links(page, prose[page.path], by_path, errors)
    return overview, libraries, errors


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, check=False).stdout.strip()


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
    if os.path.lexists(out):
        if not os.path.isdir(out) or os.listdir(out):
            sys.exit(f"docs: {out} must be a new or empty directory")
    os.makedirs(out, exist_ok=True)
    version = project_version()
    commit = git("rev-parse", "HEAD")
    released = git("tag", "--points-at", "HEAD", "--list", f"v{version}") == f"v{version}"
    index = {
        "version": version,
        "released": released,
        "commit": commit,
        "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "libraries": [],
    }
    if overview:
        index["overview"] = page_entry(overview)
        shutil.copyfile(overview.path, os.path.join(out, "index.md"))
    for name, pages in libraries:
        lib_index = next(p for p in pages if p.rel == f"{name}/index.md")
        library = {
            "slug": name,
            "title": str(lib_index.meta["title"]),
            "summary": str(lib_index.meta["summary"]),
            "order": lib_index.meta.get("order", DEFAULT_ORDER),
            "pages": sorted((page_entry(p) for p in pages), key=sort_key),
        }
        index["libraries"].append(library)
        os.makedirs(os.path.join(out, name))
        for p in pages:
            shutil.copyfile(p.path, os.path.join(out, p.rel))
        images = os.path.join(REF, name, "images")
        if os.path.isdir(images):
            shutil.copytree(images, os.path.join(out, name, "images"))
    index["libraries"].sort(key=sort_key)
    data = json.dumps(index, indent=1, ensure_ascii=False) + "\n"
    if len(data.encode("utf-8")) > INDEX_BYTES:
        sys.exit(f"docs: index.json is over {INDEX_BYTES // 1024} KiB, which the site refuses")
    with open(os.path.join(out, "index.json"), "w", encoding="utf-8") as f:
        f.write(data)
    count = sum(len(p) for _, p in libraries)
    print(f"docs: {count} pages in {len(libraries)} libraries written to {out}")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("check", "build") or (argv[1] == "build") != (len(argv) == 3):
        sys.exit(__doc__.strip().split("\n\n")[1])
    overview, libraries, errors = check()
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
        sys.exit(f"docs: {len(errors)} problem(s)")
    if argv[1] == "check":
        print(f"docs: ok ({sum(len(p) for _, p in libraries)} pages in {len(libraries)} libraries)")
    else:
        build(os.path.abspath(argv[2]), overview, libraries)


if __name__ == "__main__":
    main(sys.argv)
