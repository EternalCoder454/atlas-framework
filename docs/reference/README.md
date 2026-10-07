# Reference docs

The pages here are the Atlas Framework reference on
<https://telamon.eterneon.net/framework>. CI checks them (`tools/docs.py check`)
on every push. On main it then rebuilds the `docs-published` branch
(`tools/docs.py build`), and the site reads that branch within about five
minutes, with no site deploy. This README is not published.

## Layout

```text
docs/reference/
  index.md                  /framework: the framework overview and getting started
  <library>/index.md        /framework/<library>: the library's overview
  <library>/<page>.md       /framework/<library>/<page>
  <library>/images/*.png    pictures for that library (PNG, WebP or SVG)
```

Libraries:
- `atlas-ui` (the QML module)
- `symbols` (the icon fonts and Atlas Symbols)
- `atlas-framework-core`, `atlas-framework-ui`, `atlas-framework-system`, `atlas-framework-flatpak` (the crates)
- `template` (the app template)

A page name is the type or topic in lowercase with hyphens (`AtlasButton` → `atlas-button.md`). `index` and `images` are reserved.

## Frontmatter

Every file starts with one-line `key: value` pairs:

```yaml
---
title: AtlasButton
summary: A push button with a symbol, four variants and a busy state.
section: Buttons
order: 10
since: "1.4.0"
deprecated: Use AtlasFoo instead.
---
```

- `title` and `summary` are required.
  - `title` is the page's heading, so the body never repeats it as `#`.
  - `summary` is one sentence. It's used for search, the meta description and llms.txt.
  - Limits (UTF-16 code units, as the site counts): title 160 (a library's 120), summary 400.
- `order` (the only key read as a number) sets the sidebar position (lowest first; default 1000). `section` is the sidebar group within the library, up to 60 characters.
- `since` is the version that added the page's subject. `deprecated` says what to use instead.

## Body

The body is CommonMark plus GFM: tables, task lists, strikethrough and autolinks. The check rejects:

- raw HTML of any kind, including `<!` and `<?` and a tag split across lines (put it in backticks);
- a symbolic link anywhere under `docs/reference`;
- control, line-separator or bidi characters, or HTML, in `title`, `summary`, `section` or `deprecated`;
- an empty optional frontmatter value (remove the line instead);
- a link the checker can't parse (spaces or brackets in the address; reference-style images);
- an image that isn't what its extension says (PNG and WebP magic bytes), an SVG with scripts, event handlers, `foreignObject` or a link outside itself, or more than 32 MiB of images in total;
- a `#` heading (start at `##`);
- a code fence without a language (`qml`, `rust`, `toml`, `sh`, `cmake`, `json`, `yaml`, `cpp`, `text`);
- an indented code block (tabs too; a list item's continuation paragraph is fine);
- a relative link to a page or `#anchor` that doesn't exist;
- a link out of `docs/reference`;
- an image without alt text, or one stored anywhere other than `<library>/images/`;
- a plain `http://` link, or a link or autolink scheme other than `https:` and `mailto:`;
- a line over 10,000 characters, or a bare carriage return.

The checker is a guard, not the security boundary: the site's sanitiser is the real control for HTML and links.

Callouts use GitHub alerts: `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`. Pages link to each other with relative `.md` links (`../atlas-ui/atlas-button.md#properties`); the site rewrites them.

## A type's page

1. Two to four sentences: what it is and when to use it (and when to use something else, with a link).
2. `## Example`: the smallest QML that shows it working, usually the header comment's usage example from the type's `.qml` file.
3. `## Properties`, `## Signals`, `## Methods`, `## Enums`: tables with Name, Type, Default and Description.
   - Inherited Qt Quick members aren't listed. One line names the base type and links to its Qt page.
   - Members starting with `_` are private and never documented.
4. Optional sections such as `## Keyboard`, `## Accessibility` and `## Notes`, when there's something an app author must know.

Every public member in `api/atlas-ui.api` belongs on its type's page (`tools/docs.py check` fails on a missing type or member). A member counts as documented when it is in backticks in the first cell of a table row (`name`, `name(...)` or `Type.Value`), in a heading, or at the start of a list item; a mention in prose or in an example does not count. A member the type inherits (its `ui/<Type>.qml` root object is another Atlas.Ui type) may be left to the base type's page if the page links to it. These pages are the single source for the API: change the page in the same commit as the API, and link to it from DESIGN.md, READMEs and comments instead of describing types there.
