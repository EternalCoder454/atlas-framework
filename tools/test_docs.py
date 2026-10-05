#!/usr/bin/env python3
"""Tests for tools/docs.py: each rule gets a fixture tree in a temp folder.

    python3 tools/test_docs.py
"""

import os
import shutil
import tempfile
import unittest

import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import docs  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\0" * 16
WEBP = b"RIFF\0\0\0\0WEBPVP8 " + b"\0" * 8


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
        for bad in ("a\x01b", "a\x7fb", "a\u2028b", "a\u2029b", "a\u202eb", "a\u2066b"):
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
        self.assertTrue(self.body("![alt](images/a_(b).png)\n"))  # fails closed, whatever the message
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
        ]
        for i, svg in enumerate(bad):
            self.assertFlags(self.image_errors(f"s{i}.svg", svg), "SVG", )
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


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    unittest.main()
