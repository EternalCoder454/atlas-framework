# Reference docs

The pages here are the Atlas Framework reference on
<https://atlasos.eterneon.net/docs>. CI checks them (`tools/docs.py check`)
on every push. On main it then rebuilds the `docs-published` branch
(`tools/docs.py build`), and the site reads that branch within about five
minutes, with no site deploy. This README is not published.

## Layout

```text
docs/reference/
  index.md                  /docs: the framework overview and getting started
  <library>/index.md        /docs/<library>: the library's overview
  <library>/<page>.md       /docs/<library>/<page>
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
  - Limits: title 160 characters (a library's 120), summary 400.
- `order` sets the sidebar position (lowest first; default 1000). `section` is the sidebar group within the library, up to 60 characters.
- `since` is the version that added the page's subject. `deprecated` says what to use instead.

## Body

The body is CommonMark plus GFM: tables, task lists, strikethrough and autolinks. The check rejects:

- raw HTML of any kind;
- a `#` heading (start at `##`);
- a code fence without a language (`qml`, `rust`, `toml`, `sh`, `cmake`, `json`, `yaml`, `cpp`, `text`);
- an indented code block;
- a relative link to a page or `#anchor` that doesn't exist;
- a link out of `docs/reference`;
- an image without alt text, or one stored anywhere other than `<library>/images/`;
- a plain `http://` link.

Callouts use GitHub alerts: `> [!NOTE]`, `> [!TIP]`, `> [!WARNING]`. Pages link to each other with relative `.md` links (`../atlas-ui/atlas-button.md#properties`); the site rewrites them.

## A type's page

1. Two to four sentences: what it is and when to use it (and when to use something else, with a link).
2. `## Example`: the smallest QML that shows it working, usually the header comment's usage example from the type's `.qml` file.
3. `## Properties`, `## Signals`, `## Methods`, `## Enums`: tables with Name, Type, Default and Description.
   - Inherited Qt Quick members aren't listed. One line names the base type and links to its Qt page.
   - Members starting with `_` are private and never documented.
4. Optional sections such as `## Keyboard`, `## Accessibility` and `## Notes`, when there's something an app author must know.

Every public member in `api/atlas-ui.api` belongs on its type's page. When the API changes, change the page in the same commit.
