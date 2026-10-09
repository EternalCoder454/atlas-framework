#!/usr/bin/env python3
"""Tests for tools/docs.py: each rule gets a fixture tree in a temp folder.

    python3 tools/test_docs.py
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import docs  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 16
WEBP = b"RIFF\0\0\0\0WEBPVP8 " + b"\0" * 8

ROOT_AT_START = docs.ROOT


def page(body="Text.\n", **meta):
    fields = {"title": "A", "summary": "About A."}
    fields.update(meta)
    head = "".join(f"{k}: {v}\n" for k, v in fields.items() if v is not None)
    return f"---\n{head}---\n\n{body}"


class DocsCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="docs-test-")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.ref = os.path.join(self.tmp, "reference")
        self.saved = docs.REF
        docs.REF = self.ref
        self.addCleanup(setattr, docs, "REF", self.saved)
        docs.CUSTOM_ROOT = True  # the fixture is not under the repo root
        self.addCleanup(setattr, docs, "CUSTOM_ROOT", False)
        self.saved_api = docs.API
        docs.API = None  # fixtures have no API file unless a test sets one
        self.addCleanup(setattr, docs, "API", self.saved_api)
        self.write("lib/index.md", page(title="Lib"))

    def write(self, rel, content):
        path = os.path.join(self.ref, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb" if isinstance(content, bytes) else "w", **({} if isinstance(content, bytes) else {"encoding": "utf-8"})) as f:
            f.write(content)
        return path

    def link(self, rel, target):
        path = os.path.join(self.ref, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        os.symlink(target, path)

    def errors(self):
        return docs.check()[2]

    def body(self, text, **meta):
        self.write("lib/a.md", page(text, **meta))
        return self.errors()

    def assertFlags(self, errors, needle):
        self.assertTrue(any(needle in e for e in errors), f"no error with {needle!r} in {errors}")

    def assertClean(self, errors):
        self.assertEqual(errors, [])


class Reports(DocsCase):
    """What `check` prints about a tree it does not trust."""

    def test_control_characters_in_names_never_reach_the_output(self):
        import contextlib
        import io
        self.write("lib/bad\x1b[31m\rname.md", page())
        self.write("odd\n::set-output name=x::y.md", page())
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit):
            docs.main(["docs.py", "--root", self.ref, "check"])
        text = err.getvalue()
        self.assertIn("bad?[31m?name", text)
        self.assertNotRegex(text, "[\x00-\x08\x0b-\x1f\x7f]")
        self.assertFalse(any(line.startswith("::") for line in text.splitlines()))


class ApiCoverage(DocsCase):
    """Every type and public member in the API file is on a telamon-ui page."""

    API = (
        "TelamonButton.enum Variant: Default = 0\n"
        "TelamonButton.enum Variant: Ghost = 3\n"
        "TelamonButton.property busy: bool\n"
        "TelamonButton.property _hidden: int\n"
        "TelamonButton.signal pressed()\n"
        "TelamonButton.method open(QVariant x): void\n"
        "TelamonButton.type\n"
        "DataTable.property busy: bool\n"
        "DataTable.property rows: int\n"
        "DataTable.type\n"
    )
    BUTTON = (
        "## Properties\n\n| Name | Type |\n|---|---|\n| `busy` | `bool` |\n\n"
        "## Signals\n\n| Name | Description |\n|---|---|\n| `pressed()` | Pressed. |\n\n"
        "## Methods\n\n- `open(x)`: opens it.\n\n"
        "## Enums\n\n| Value | Description |\n|---|---|\n| `TelamonButton.Default` | Plain. |\n| `TelamonButton.Ghost` | Bare. |\n"
    )
    TABLE = "Like [TelamonButton](telamon-button.md).\n\n| Name | Type |\n|---|---|\n| `rows` | `int` |\n"

    def setUp(self):
        super().setUp()
        os.makedirs(os.path.join(self.tmp, "api"))
        os.makedirs(os.path.join(self.tmp, "ui"))
        self.api = os.path.join(self.tmp, "api", "t.api")
        self.set_api(self.API)
        self.qml("DataTable", "import QtQuick\n\nTelamonButton {\n}\n")
        self.qml("TelamonButton", "import QtQuick.Controls as QQC2\n\nQQC2.Button {\n}\n")
        docs.API = self.api
        self.write("telamon-ui/index.md", page(title="Telamon.Ui"))
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON))
        self.write("telamon-ui/data-table.md", page(self.TABLE))

    def set_api(self, text):
        with open(self.api, "w") as f:
            f.write(text)

    def qml(self, type_name, text):
        with open(os.path.join(self.tmp, "ui", type_name + ".qml"), "w") as f:
            f.write(text)

    def test_complete_pages_pass(self):
        self.assertClean(self.errors())

    def test_missing_page(self):
        os.remove(os.path.join(self.ref, "telamon-ui/data-table.md"))
        self.assertFlags(self.errors(), "telamon-ui/data-table.md: no page for DataTable")

    def test_missing_member_names_page_and_member(self):
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON.replace("- `open(x)`: opens it.", "Nothing.")
                                                    .replace("| `TelamonButton.Ghost` | Bare. |\n", "")))
        errors = self.errors()
        self.assertFlags(errors, "telamon-ui/telamon-button.md: `open` of TelamonButton")
        self.assertFlags(errors, "`Ghost` of TelamonButton")

    def test_name_in_prose_does_not_count(self):
        # Only a table's first cell, a heading or a list item's start documents a name.
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON.replace("| `busy` | `bool` |\n", "")
                                                    + "\nWhile `busy` it spins.\n"))
        self.assertFlags(self.errors(), "telamon-button.md: `busy`")

    def test_qualified_name_in_another_cell_does_not_count(self):
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON.replace("| `busy` | `bool` |", "| `x` | `Foo.busy` |")))
        self.assertFlags(self.errors(), "telamon-button.md: `busy`")

    def test_inherited_member_needs_link_to_base_page(self):
        self.write("telamon-ui/data-table.md", page(self.TABLE.replace("Like [TelamonButton](telamon-button.md).", "Like TelamonButton.")))
        self.assertFlags(self.errors(), "telamon-ui/data-table.md: `busy`")

    def test_a_link_to_a_type_that_is_not_the_base_does_not_count(self):
        self.qml("DataTable", "import QtQuick\n\nItem {\n}\n")
        self.assertFlags(self.errors(), "telamon-ui/data-table.md: `busy`")

    def test_inherited_member_must_be_on_the_base_page(self):
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON.replace("| `busy` | `bool` |\n", "")))
        errors = self.errors()
        self.assertFlags(errors, "telamon-button.md: `busy`")
        self.assertFlags(errors, "data-table.md: `busy`")

    def test_inheritance_is_followed_through_several_types(self):
        self.set_api(self.API + "TelamonSuperTable.property busy: bool\nTelamonSuperTable.type\n")
        self.qml("TelamonSuperTable", "DataTable {\n}\n")
        self.write("telamon-ui/telamon-super-table.md", page("Like [DataTable](data-table.md).\n"))
        self.assertClean(self.errors())

    def test_private_members_are_not_required(self):
        self.assertNotIn("_hidden", " ".join(self.errors()))

    def test_unrecognised_line(self):
        self.set_api(self.API + "garbage\n")
        self.assertFlags(self.errors(), "unrecognised line")

    def test_base_lines_are_not_members(self):
        self.set_api(self.API + "TelamonButton.base QQuickItem\n")
        self.assertClean(self.errors())

    def test_names_in_fences_do_not_count(self):
        self.write("telamon-ui/telamon-button.md", page(self.BUTTON.replace("- `open(x)`: opens it.",
                                                    "~~~qml\n```\n- `open(x)`: no\n```\n~~~")))
        self.assertFlags(self.errors(), "`open`")

    def test_no_api_skips_the_check(self):
        docs.API = None
        self.write("telamon-ui/telamon-button.md", page("Nothing.\n"))
        self.assertClean(self.errors())

    def test_cli_api_option(self):
        self.write("telamon-ui/telamon-button.md", page("`busy`\n"))
        with self.assertRaises(SystemExit):
            docs.main(["docs.py", "--root", self.ref, "--api", self.api, "check"])

    def test_page_slug(self):
        self.assertEqual(docs.page_slug("TelamonButton"), "telamon-button")
        self.assertEqual(docs.page_slug("DataTable"), "data-table")
        self.assertEqual(docs.page_slug("AccessibilityState"), "accessibility-state")


class HappyPath(DocsCase):
    def test_clean_tree_checks_and_builds(self):
        self.write("index.md", page("See [lib](lib/a.md#heading).\n", title="Overview"))
        self.write("lib/a.md", page(
            "## Heading\n\n```qml\nItem {}\n```\n\nA [link](index.md \"t\") and ![alt](images/p.png).\n"
            "<https://example.org> <me@example.org>\n\n> [!NOTE]\n> Note.\n",
            order=5, since='"1.4.0"', section="S"))
        self.write("lib/images/p.png", PNG)
        self.write("lib/images/w.webp", WEBP)
        self.write("lib/images/s.svg", '<svg xmlns="http://www.w3.org/2000/svg"><use href="#x"/></svg>')
        overview, libraries, errors = docs.check()
        self.assertClean(errors)
        out = os.path.join(self.tmp, "out")
        docs.build(out, overview, libraries)
        for rel in ("index.md", "index.json", "lib/a.md", "lib/images/p.png"):
            self.assertTrue(os.path.isfile(os.path.join(out, rel)), rel)
        self.assertEqual([n for n in os.listdir(self.tmp) if ".tmp-" in n], [])


class Symlinks(DocsCase):
    def test_symlinked_page(self):
        self.write("real.txt", "x")
        self.link("lib/b.md", os.path.join(self.ref, "real.txt"))
        self.assertFlags(self.errors(), "symbolic links are not allowed")

    def test_symlinked_library_dir(self):
        os.makedirs(os.path.join(self.tmp, "elsewhere"))
        self.link("other", os.path.join(self.tmp, "elsewhere"))
        self.assertFlags(self.errors(), "docs/reference/other: symbolic links")

    def test_symlinked_images_dir_and_file(self):
        os.makedirs(os.path.join(self.tmp, "imgs"))
        self.link("lib/images", os.path.join(self.tmp, "imgs"))
        self.assertFlags(self.errors(), "lib/images: symbolic links")
        os.unlink(os.path.join(self.ref, "lib/images"))
        self.write("lib/images/real.png", PNG)
        self.link("lib/images/l.png", os.path.join(self.ref, "lib/images/real.png"))
        self.assertFlags(self.errors(), "l.png: symbolic links")

    def test_build_copies_only_validated_files(self):
        self.write("lib/images/p.png", PNG)
        overview, libraries, errors = docs.check()
        self.assertClean(errors)
        self.assertEqual([os.path.basename(p) for p in libraries[0].images], ["p.png"])


class Frontmatter(DocsCase):
    def test_only_order_is_a_number(self):
        self.write("lib/a.md", page(title="1.50", order="2"))
        _, libraries, errors = docs.check()
        self.assertClean(errors)
        meta = next(p for p in libraries[0].pages if p.rel == "lib/a.md").meta
        self.assertEqual(meta["title"], "1.50")
        self.assertEqual(meta["order"], 2)

    def test_bad_order(self):
        self.assertFlags(self.body("x\n", order="soon"), "`order` must be a number")

    def test_empty_optional_values(self):
        for key in ("order", "since", "section", "deprecated"):
            self.assertFlags(self.body("x\n", **{key: '""'}), f"`{key}` is empty")

    def test_control_and_bidi_characters(self):
        for bad in ("a\x01b", "a\x7fb", "a\u2028b", "a\u2029b", "a\u202eb", "a\u2066b", "a\x85b", "a\u200bb", "a\u061cb", "a\ufeffb"):
            for key in ("title", "summary", "section", "deprecated"):
                self.assertFlags(self.body("x\n", **{key: bad}), "bidi character")

    def test_html_in_fields(self):
        for key in ("title", "summary", "section", "deprecated"):
            self.assertFlags(self.body("x\n", **{key: "a <b>x</b>"}), "raw HTML")
        self.assertClean(self.body("x\n", summary="`Symbols.<Name>` works"))

    def test_lengths_count_utf16_units(self):
        self.assertClean(self.body("x\n", title="a" * 160))
        self.assertFlags(self.body("x\n", title="a" * 159 + "\U0001F600"), "longer than 160")
        self.assertClean(self.body("x\n", title="é" * 160))

    def test_since_needs_ascii_digits(self):
        self.assertFlags(self.body("x\n", since="١.٢.٣"), "`since`")
        self.assertFlags(self.body("x\n", since="1.4"), "`since`")


class Slugs(DocsCase):
    def test_trailing_newline_not_a_slug(self):
        self.assertFalse(docs.SLUG.fullmatch("abc\n"))
        self.assertTrue(docs.SLUG.fullmatch("abc-d"))

    def test_page_name_with_newline(self):
        self.write("lib/a\n.md", page())
        self.assertFlags(self.errors(), "lowercase-with-hyphens")


class Links(DocsCase):
    def test_title_forms(self):
        self.write("lib/b.md", page())
        for t in ('"t"', "'t'", "(t)"):
            self.assertClean(self.body(f"[b](b.md {t})\n"))

    def test_remote_image_with_any_title(self):
        for t in ("", ' "t"', " 't'", " (t)"):
            self.assertFlags(self.body(f"![alt](https://example.org/x.png{t})\n"), "remote image")

    def test_missing_page_and_anchor(self):
        self.assertFlags(self.body("[b](nope.md)\n"), "does not exist")
        self.assertFlags(self.body("[b](a.md#nope)\n"), "no heading")

    def test_reference_definitions(self):
        self.assertFlags(self.body("[x][r]\n\n[r]: nope.md\n"), "does not exist")
        self.assertFlags(self.body("[x][r]\n\n   [r]: <http://example.org>\n"), "plain http")
        self.assertFlags(self.body("[x][r]\n\n[r]: ../../outside.md\n"), "leaves docs/reference")
        self.assertClean(self.body("[x][r]\n\n[r]: a.md\n"))

    def test_autolink_schemes(self):
        self.assertFlags(self.body("<javascript:alert(1)>\n"), "scheme not allowed")
        self.assertFlags(self.body("<ftp://example.org>\n"), "scheme not allowed")
        self.assertFlags(self.body("<http://example.org>\n"), "plain http")
        self.assertClean(self.body("<https://example.org> <mailto:me@example.org>\n"))

    def test_unparseable_links(self):
        self.assertFlags(self.body("[x](<a b.md>)\n"), "can't parse")
        self.assertFlags(self.body("![alt](images/a_(b).png)\n"), "missing image: images/a_(b")
        self.assertFlags(self.body("![alt][ref]\n"), "can't parse")

    def test_image_nested_in_link_is_checked(self):
        self.assertFlags(self.body("[![alt](https://example.org/x.png)](a.md)\n"), "remote image")

    def test_percent_decoding(self):
        self.assertFlags(self.body("[x](%2e%2e/%2e%2e/%2e%2e/etc/passwd)\n"), "leaves docs/reference")
        self.assertFlags(self.body("[x](a.md#%48ead)\n"), "no heading `#Head`")
        self.assertFlags(self.body("[x](a.md%00)\n"), "control")
        self.write("lib/b.md", page("## Hello World\n"))
        self.assertClean(self.body("[x](b.md#hello%2Dworld)\n"))

    def test_image_rules(self):
        self.write("lib/images/p.png", PNG)
        self.assertFlags(self.body("![](images/p.png)\n"), "without alt text")
        self.assertFlags(self.body("![a](images/none.png)\n"), "missing image")
        self.assertFlags(self.body("![a](b.png)\n"), "missing image")
        self.assertClean(self.body("![a](images/p.png)\n"))

    def test_http_and_absolute(self):
        self.assertFlags(self.body("[x](http://example.org)\n"), "plain http")
        self.assertFlags(self.body("[x](/lib/a.md)\n"), "absolute link")

    def test_link_spanning_lines(self):
        self.assertFlags(self.body("[x\ny](nope.md)\n"), "does not exist")


class Anchors(DocsCase):
    def test_github_collision_rule(self):
        self.write("lib/b.md", page("## a\n\n## a\n\n## a-1\n\n## a\n"))
        _, libraries, _ = docs.check()
        b = next(p for p in libraries[0].pages if p.rel == "lib/b.md")
        self.assertEqual(b.anchors, {"a", "a-1", "a-1-1", "a-2"})
        self.assertClean(self.body("[x](b.md#a-1-1) [y](b.md#a-2)\n"))


class Fences(DocsCase):
    def test_fence_needs_language(self):
        self.assertFlags(self.body("```\ncode\n```\n"), "without a language")

    def test_unclosed_fence(self):
        self.assertFlags(self.body("```qml\ncode\n"), "never closed")

    def test_inline_triple_backticks_are_prose(self):
        self.assertClean(self.body("Use ```inline``` here.\n\n## After\n\n[x](a.md#after)\n"))
        self.assertFlags(self.body("```inline``` <b>x</b>\n"), "raw HTML")

    def test_fence_in_list_and_quote(self):
        self.assertClean(self.body("- item\n\n  ```qml\n  <b>x</b>\n  ```\n\n- next\n"))
        self.assertClean(self.body("> ```qml\n> <b>x</b>\n> ```\n"))
        self.assertClean(self.body("1. ```qml\n   <b>x</b>\n   ```\n"))
        self.assertFlags(self.body("- item\n\n  ```\n  x\n  ```\n"), "without a language")
        self.assertFlags(self.body("> ```\n> x\n> ```\n"), "without a language")

    def test_list_continuation_is_not_code(self):
        self.assertClean(self.body("- item\n\n    continued paragraph\n\n- next\n"))

    def test_indented_and_tab_code(self):
        self.assertFlags(self.body("Para.\n\n    code\n"), "indented code block")
        self.assertFlags(self.body("Para.\n\n\tcode\n"), "indented code block")
        self.assertClean(self.body("Para\n    continued\n"))


class RawHtml(DocsCase):
    def test_tags(self):
        for text in ("<b>x</b>\n", "<!-- c -->\n", "<!DOCTYPE html>\n", "<?php x ?>\n", "<br/>\n"):
            self.assertFlags(self.body(text), "put it in backticks")

    def test_tag_split_across_lines(self):
        self.assertFlags(self.body('text <div\nclass="x">\n'), "raw HTML")
        self.assertFlags(self.body("<img\nsrc=x>\n"), "raw HTML")

    def test_code_spans_are_exempt_even_across_lines(self):
        self.assertClean(self.body("A `<b>` and `two\nlines <b>` here.\n"))

    def test_line_number_of_the_html(self):
        errors = self.body("one\ntwo <b>x</b>\n")
        self.assertFlags(errors, "a.md:7:")

    def test_h1(self):
        self.assertFlags(self.body("# Title\n"), "`#` heading")


class Images(DocsCase):
    def image_errors(self, name, data):
        self.write(f"lib/images/{name}", data)
        return self.errors()

    def test_magic_bytes(self):
        self.assertFlags(self.image_errors("a.png", b"GIF89a"), "not a PNG")
        self.assertFlags(self.image_errors("b.webp", b"RIFF0000WAVE"), "not a WebP")
        self.assertFlags(self.image_errors("c.webp", b"short"), "not a WebP")

    def test_svg_rules(self):
        bad = [
            "<svg><script>x</script></svg>",
            '<svg onload="x()"/>',
            "<svg><a onclick = 'x'/></svg>",
            "<svg><foreignObject/></svg>",
            '<svg><a href="https://example.org"/></svg>',
            '<svg><image xlink:href="javascript:x"/></svg>',
            "<svg><use href='data:x'/></svg>",
            b"\xff\xfe<\0s\0v\0g\0/\0>\0",
            b"<svg>\xff</svg>",
            b"<\0s\0v\0g\0/\0>\0",
            "<!DOCTYPE svg><svg/>",
            '<!DOCTYPE svg [<!ENTITY x "y">]><svg/>',
            "<svg><x:script/></svg>",
            "<svg><set attributeName='x'/></svg>",
            "<svg><animateTransform/></svg>",
            '<svg><rect style="fill:url(https://e.org/x)"/></svg>',
            "<svg><style>@import 'x';</style></svg>",
            "<svg><style>a{fill:url(x)}</style></svg>",
        ]
        for i, svg in enumerate(bad):
            self.assertFlags(self.image_errors(f"s{i}.svg", svg), "SVG")
            os.unlink(os.path.join(self.ref, f"lib/images/s{i}.svg"))
        self.assertClean(self.image_errors("ok.svg", '<svg><use xlink:href="#a"/><g id="a"/></svg>'))

    def test_wrong_type_and_size(self):
        self.assertFlags(self.image_errors("a.gif", b"GIF89a"), "only PNG, WebP and SVG")
        os.unlink(os.path.join(self.ref, "lib/images/a.gif"))
        self.assertFlags(self.image_errors("big.png", PNG + b"\0" * docs.IMAGE_BYTES), "over 4 MiB")

    def test_total_cap(self):
        saved = (docs.IMAGES_TOTAL_BYTES, docs.IMAGE_BYTES)
        docs.IMAGES_TOTAL_BYTES = 1000
        self.addCleanup(setattr, docs, "IMAGES_TOTAL_BYTES", saved[0])
        self.write("lib/images/a.png", PNG + b"\0" * 600)
        self.write("lib/images/b.png", PNG + b"\0" * 600)
        self.assertFlags(self.errors(), "images add up to")


class Limits(DocsCase):
    def test_overview_counts_toward_max_pages(self):
        saved = docs.MAX_PAGES
        docs.MAX_PAGES = 2
        self.addCleanup(setattr, docs, "MAX_PAGES", saved)
        self.write("lib/a.md", page())
        self.assertClean(self.errors())
        self.write("index.md", page(title="Overview"))
        self.assertFlags(self.errors(), "3 pages")

    def test_build_fails_without_libraries(self):
        os.unlink(os.path.join(self.ref, "lib/index.md"))
        os.rmdir(os.path.join(self.ref, "lib"))
        self.write("index.md", page(title="Overview"))
        out = os.path.join(self.tmp, "out")
        with self.assertRaises(SystemExit) as cm:
            docs.main(["docs.py", "--root", self.ref, "build", out])
        self.assertIn("problem", str(cm.exception))
        self.assertFalse(os.path.exists(out))

    def test_cli_root_option(self):
        docs.REF = "/nonexistent"
        docs.main(["docs.py", "--root", self.ref, "check"])  # exits only on problems
        self.assertEqual(docs.REF, self.ref)

    def test_build_leaves_no_partial_output_on_failure(self):
        overview, libraries, errors = docs.check()
        self.assertClean(errors)
        out = os.path.join(self.tmp, "out")
        saved = docs.INDEX_BYTES
        docs.INDEX_BYTES = 10
        self.addCleanup(setattr, docs, "INDEX_BYTES", saved)
        with self.assertRaises(SystemExit):
            docs.build(out, overview, libraries)
        self.assertEqual(os.listdir(self.tmp), ["reference"])


class Round2(DocsCase):
    def test_escaped_backticks_do_not_make_a_span(self):
        self.assertFlags(self.body("a \\`<b>x</b> and \\`\n"), "raw HTML")
        self.assertClean(self.body("a `<b>x</b>` and \\\\`<c>` d\n"))

    def test_code_spans_do_not_pair_across_blocks(self):
        self.assertFlags(self.body("- a `x <b>y</b>\n- b` z\n"), "raw HTML")
        self.assertFlags(self.body("a `x <b>\n## H `\n"), "raw HTML")
        self.assertFlags(self.body("| a `x <b> |\n| b ` |\n"), "raw HTML")

    def test_fence_ends_with_its_quote(self):
        self.assertFlags(self.body("> ```qml\n> x\n\n<b>raw</b>\n"), "raw HTML")
        self.assertFlags(self.body("> ```qml\n> x\n<b>raw</b>\n"), "raw HTML")

    def test_fence_ends_with_its_list_item(self):
        self.assertFlags(self.body("- item\n\n  ```qml\n  x\n\nPara <b>raw</b>\n"), "raw HTML")

    def test_quote_marker_inside_a_top_level_fence_is_content(self):
        self.assertClean(self.body("```qml\n> ```\n<b>x</b>\n```\n"))

    def test_bare_cr(self):
        self.write("lib/a.md", page("a\rb\n").encode())
        self.assertFlags(self.errors(), "bare CR")
        self.write("lib/a.md", page("a\nb\n").replace("\n", "\r\n").encode())
        self.assertClean(self.errors())

    def test_reference_definition_after_list_marker(self):
        self.assertFlags(self.body("- [a]: javascript:x\n"), "scheme not allowed")
        self.assertFlags(self.body("1. [a]: nope.md\n"), "does not exist")

    def test_any_lt_letter_is_html(self):
        for text in ("<img/src=x>\n", "<a/onclick=x>\n", "x <!x\n", "a <?x\n", "</b>\n"):
            self.assertFlags(self.body(text), "raw HTML")
        self.assertClean(self.body("1 < 2 and <https://example.org> and `<b>`\n"))

    def test_setext_headings(self):
        self.assertFlags(self.body("Title\n=====\n"), "`#` heading")
        self.assertClean(self.body("Sub head\n--------\n\n[x](a.md#sub-head)\n"))
        self.assertFlags(self.body("Sub head\n--------\n\n[x](a.md#nope)\n"), "no heading")
        self.assertClean(self.body("Para\n\n---\n\nText\n\n[x](a.md)\n"))
        self.assertClean(self.body("- item\n---\n"))

    def test_long_lines(self):
        self.assertFlags(self.body("a" * 10001 + "\n"), "over 10000 characters")
        self.assertClean(self.body("## " + "# " * 2000 + "\n"))

    def test_order_cap(self):
        self.assertClean(self.body("x\n", order="1000000000"))
        for bad in ("1000000001", "9" * 13, "-1000000001", "1." + "0" * 20):
            self.assertFlags(self.body("x\n", order=bad), "`order` must be")

    def test_overview_remote_image_message(self):
        self.write("index.md", page("![a](https://example.org/x.png)\n", title="O"))
        errors = self.errors()
        self.assertFlags(errors, "remote image")
        self.assertFalse(any("None" in e for e in errors), errors)

    def test_symlinked_reference_root_and_ancestors(self):
        repo = os.path.join(self.tmp, "repo")
        real = os.path.join(self.tmp, "realdocs")
        shutil.copytree(self.ref, os.path.join(real, "reference"))
        os.makedirs(repo)
        os.symlink(real, os.path.join(repo, "docs"))
        saved = (docs.ROOT, docs.CUSTOM_ROOT)
        self.addCleanup(lambda: (setattr(docs, "ROOT", saved[0]), setattr(docs, "CUSTOM_ROOT", saved[1])))
        docs.ROOT, docs.CUSTOM_ROOT = repo, False
        docs.REF = os.path.join(repo, "docs", "reference")
        self.assertFlags(self.errors(), "symbolic link")
        docs.CUSTOM_ROOT = True  # --root given: the caller chose the path
        self.assertClean(self.errors())


class BuildAndGit(DocsCase):
    def make_repo(self, tag):
        repo = os.path.join(self.tmp, "repo")
        os.makedirs(repo)
        with open(os.path.join(repo, "CMakeLists.txt"), "w") as f:
            f.write("project(telamon-framework VERSION 1.2.3)\n")
        env = {"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
               "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
               "GIT_COMMITTER_EMAIL": "t@t", "PATH": os.environ["PATH"]}
        for args in [["init", "-q"], ["add", "."], ["commit", "-q", "-m", "x"]] + ([["tag", tag]] if tag else []):
            subprocess.run(["git", "-C", repo, *args], check=True, env=env, capture_output=True)
        saved = docs.ROOT
        self.addCleanup(setattr, docs, "ROOT", saved)
        docs.ROOT = repo

    def build(self, out):
        overview, libraries, errors = docs.check()
        self.assertClean(errors)
        docs.build(out, overview, libraries)

    def released(self, tag):
        self.make_repo(tag)
        out = os.path.join(self.tmp, "out")
        self.build(out)
        with open(os.path.join(out, "index.json"), encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(len(data["commit"]), 40)
        return data["released"]

    def test_released_with_and_without_the_tag(self):
        self.assertTrue(self.released("v1.2.3"))

    def test_not_released_without_the_tag(self):
        self.assertFalse(self.released(None))

    def test_not_released_with_another_tag(self):
        self.assertFalse(self.released("v9.9.9"))

    def test_git_failure_stops_the_build(self):
        docs.ROOT = os.path.join(self.tmp, "norepo")
        os.makedirs(docs.ROOT)
        with open(os.path.join(docs.ROOT, "CMakeLists.txt"), "w") as f:
            f.write("project(telamon-framework VERSION 1.2.3)\n")
        self.addCleanup(setattr, docs, "ROOT", ROOT_AT_START)
        overview, libraries, errors = docs.check()
        with self.assertRaises(SystemExit) as cm:
            docs.build(os.path.join(self.tmp, "out"), overview, libraries)
        self.assertIn("git", str(cm.exception))
        self.assertFalse(os.path.exists(os.path.join(self.tmp, "out")))

    def test_out_dir_states(self):
        self.make_repo(None)
        empty = os.path.join(self.tmp, "empty")
        os.makedirs(empty)
        self.build(empty)
        self.assertTrue(os.path.isfile(os.path.join(empty, "index.json")))
        full = os.path.join(self.tmp, "full")
        os.makedirs(full)
        with open(os.path.join(full, "keep"), "w") as f:
            f.write("x")
        overview, libraries, _ = docs.check()
        with self.assertRaises(SystemExit) as cm:
            docs.build(full, overview, libraries)
        self.assertIn("new or empty", str(cm.exception))
        self.assertEqual(os.listdir(full), ["keep"])
        target = os.path.join(self.tmp, "target")
        os.makedirs(target)
        link = os.path.join(self.tmp, "link")
        os.symlink(target, link)
        with self.assertRaises(SystemExit):
            docs.build(link, overview, libraries)
        self.assertEqual(os.listdir(target), [])


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    unittest.main()
