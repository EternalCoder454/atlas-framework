//! Guards of the QML of Telamon.Ui (and of the gallery and the app template,
//! which apps copy) that draws or opens what other programs sent. They read
//! the QML source, so a new `Text`, link, image or script that skips a rule
//! fails here, in CI, and not in a review three releases later.
//!
//! The rules (docs/SECURITY.md, "Rich text", "Opening links", "Fetching"):
//!
//! - Text from outside (file names, model rows, D-Bus and journal text, URLs)
//!   is drawn as plain text: every `Text`, `Label`, `Heading`, `TextEdit` and
//!   `TextArea` says `textFormat: Text.PlainText`; nothing asks for rich,
//!   styled, Markdown or auto-detected text except the components on
//!   `RICH` below, each with its reason; `TelamonLabel` (plain by default) is
//!   never switched away from it.
//! - A link is opened only through `TelamonPortal.openUrl` (scheme, host and
//!   control-character rules in C++), from a list of files, with a URL that is
//!   checked first. `Qt.openUrlExternally` and `Qt.openUrl` are not used.
//!   `linkActivated` only forwards the link to the app.
//! - QML does not run text as code (`eval`, `Function`, `Qt.include`, a
//!   non-literal `Qt.createQmlObject`, a `Loader` with a `source` string) and
//!   does not fetch: no `XMLHttpRequest`, `fetch`, `WebSocket`, web views, no
//!   `http:` literal; an `Image` source from the app goes through a check
//!   (`IMAGES` below).
//! - The checker itself is tested: snippets that must pass and must fail.

use std::fs;
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------- the rules

/// Files (relative to the repository) that may contain rich text, and what
/// text. Each entry: (file, token, how many times, why it is safe).
const RICH: &[(&str, &str, usize, &str)] = &[
    (
        "ui/NotesText.qml",
        "RichText",
        1,
        "release notes: the app's backend sends a sanitised HTML fragment (no images, no styles, \
         https links), and a link only opens when the app's backend.isSafeLink says so",
    ),
    (
        "ui/TelamonAutocompleteField.qml",
        "StyledText",
        1,
        "the suggestion is drawn by internals.mark(), which escapes every character of the \
         suggestion (& < >) and adds only <b> around the match; see the test in tests/fields",
    ),
];

/// Text types: the last segment of the type name (`QQC2.Label` is `Label`).
const TEXT_TYPES: &[&str] = &[
    "Text",
    "Label",
    "Heading",
    "SelectableLabel",
    "TextEdit",
    "TextArea",
];

/// Types whose instances are Telamon.Ui text: they must never be given a
/// `textFormat` that is not plain (`NotesText` is the rich one on `RICH`).
const PLAIN_BY_DEFAULT: &[&str] = &["TelamonLabel", "TelamonTextArea", "TelamonTextField"];

/// Files that make a `NotesText` besides its own: the gallery demo shows it
/// with a literal fragment.
const NOTES_USERS: &[(&str, &str)] = &[(
    "ui/gallery/demos/NotesTextDemo.qml",
    "a literal sample fragment, no backend",
)];

/// Files with a `Loader { source: ... }` and why the string is not from outside.
const LOADER_SOURCES: &[(&str, &str)] = &[(
    "ui/gallery/ControlsPage.qml",
    "the gallery loads its own demos: a fixed qrc prefix and the name of a type of its own list",
)];

/// Files the Text rule leaves to their owner. The app template is copied by
/// every new app and is checked as part of the template's own tests; it needs
/// `textFormat: Text.PlainText` on its labels too (see the report of this change).
const TEXT_PENDING: &[(&str, &str)] = &[(
    "template/qml/MainPage.qml",
    "a Label in the template's sample page: the template is edited with the template's own change",
)];

/// Who may call `TelamonPortal.openUrl`, with what argument, and why that
/// argument is checked.
const OPENERS: &[(&str, &[&str], &str)] = &[(
    "ui/TelamonAboutPage.qml",
    &[
        "TelamonApp.sourceUrl",
        "TelamonApp.issuesUrl",
        "modelData.url",
    ],
    "sourceUrl and issuesUrl are built by TelamonApp from a validated repository name; modelData.url \
     is an entry of `links` that _links accepted (http, https or mailto only); TelamonPortal.openUrl \
     checks the rest",
)];

/// Files that make an `Image`/`AnimatedImage` and the `source` it must have:
/// the app's `source` goes through a check first.
const IMAGES: &[(&str, &[&str], &str)] = &[
    (
        "ui/TelamonAvatar.qml",
        &["root._safeSource"],
        "TelamonAvatar.source is vetted by _safeSource: local files, qrc: and image: always, \
         https only with allowRemote",
    ),
    (
        "ui/TelamonChoiceCard.qml",
        &["control._safeSource"],
        "TelamonChoiceCard.source is vetted by _safeSource: local files, qrc: and image: always, \
         https only with allowRemote",
    ),
    (
        "ui/TelamonScreenshotCarousel.qml",
        &["slide.loadSource", "zoom.source"],
        "the carousel vets every source (priv.vet): local files, qrc:, image:, https only with \
         allowRemote",
    ),
];

// ------------------------------------------------------------ the QML reader

struct Source {
    /// Relative to the repository, with `/`.
    path: String,
    text: String,
    /// `text` with the inside of comments and string literals blanked
    /// (same length, same line breaks), so braces and names can be found
    /// without a string or a comment fooling the search.
    masked: String,
}

fn repo() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn walk(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries {
        let path = entry.unwrap().path();
        if path.is_dir() {
            walk(&path, out);
        } else if matches!(
            path.extension().and_then(|e| e.to_str()),
            Some("qml" | "js")
        ) {
            out.push(path);
        }
    }
}

/// The QML and JS of `ui/` (the module and the gallery) and of `template/`.
fn sources() -> Vec<Source> {
    let root = repo();
    let mut files = Vec::new();
    for dir in ["ui", "template"] {
        walk(&root.join(dir), &mut files);
    }
    files.sort();
    let out: Vec<Source> = files
        .iter()
        .map(|p| {
            let text = fs::read_to_string(p).unwrap();
            Source {
                path: p
                    .strip_prefix(&root)
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/"),
                masked: mask(&text),
                text,
            }
        })
        .collect();
    assert!(out.len() > 150, "found only {} QML files", out.len());
    out
}

/// `text` with comments and the inside of string, template and regular
/// expression literals replaced by spaces (newlines kept).
fn mask(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = b.to_vec();
    let blank = |out: &mut Vec<u8>, from: usize, to: usize| {
        for byte in &mut out[from..to] {
            if *byte != b'\n' {
                *byte = b' ';
            }
        }
    };
    let mut i = 0;
    // The last byte that is not white space or part of a comment: a `/` after
    // an operator or a bracket starts a regular expression, after a name it
    // divides.
    let mut prev = b'\n';
    while i < b.len() {
        match b[i] {
            b'/' if b.get(i + 1) == Some(&b'/') => {
                let start = i;
                while i < b.len() && b[i] != b'\n' {
                    i += 1;
                }
                blank(&mut out, start, i);
                continue;
            }
            b'/' if b.get(i + 1) == Some(&b'*') => {
                let start = i;
                i += 2;
                while i < b.len() && !(b[i] == b'*' && b.get(i + 1) == Some(&b'/')) {
                    i += 1;
                }
                i = (i + 2).min(b.len());
                blank(&mut out, start, i);
                continue;
            }
            q @ (b'"' | b'\'' | b'`') => {
                let start = i + 1;
                i += 1;
                while i < b.len() && b[i] != q && !(b[i] == b'\n' && q != b'`') {
                    if b[i] == b'\\' {
                        i += 1;
                    }
                    i += 1;
                }
                let end = i.min(b.len());
                blank(&mut out, start, end);
                i = end + 1;
                prev = q;
                continue;
            }
            b'/' if b"(,=:[!&|?{};\n".contains(&prev) => {
                // A regular expression literal.
                let start = i + 1;
                i += 1;
                let mut class = false;
                while i < b.len() && b[i] != b'\n' && (class || b[i] != b'/') {
                    match b[i] {
                        b'\\' => i += 1,
                        b'[' => class = true,
                        b']' => class = false,
                        _ => {}
                    }
                    i += 1;
                }
                let end = i.min(b.len());
                blank(&mut out, start, end);
                i = end + 1;
                prev = b'/';
                continue;
            }
            c if !c.is_ascii_whitespace() => prev = c,
            _ => {}
        }
        i += 1;
    }
    String::from_utf8(out).unwrap()
}

fn line_of(text: &str, offset: usize) -> usize {
    text[..offset].matches('\n').count() + 1
}

fn is_name(c: u8) -> bool {
    c.is_ascii_alphanumeric() || c == b'_' || c == b'.'
}

/// One `Type { ... }`: the name as written, the line, and the byte range of
/// the braces' inside in the source.
struct Element {
    name: String,
    line: usize,
    open: usize,
    close: usize,
}

impl Element {
    /// The last segment of the name: `QQC2.Label` is `Label`.
    fn base(&self) -> &str {
        self.name.rsplit('.').next().unwrap()
    }
}

/// Every `Name {` of the masked source whose last segment starts with a
/// capital: an object of that type (or an `enum`, which no rule asks about).
fn elements(src: &Source) -> Vec<Element> {
    let b = src.masked.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if !(b[i].is_ascii_alphabetic() || b[i] == b'_') || (i > 0 && is_name(b[i - 1])) {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && is_name(b[i]) {
            i += 1;
        }
        let name = &src.masked[start..i];
        let mut j = i;
        while j < b.len() && b[j].is_ascii_whitespace() {
            j += 1;
        }
        let last = name.rsplit('.').next().unwrap();
        if b.get(j) == Some(&b'{') && last.as_bytes()[0].is_ascii_uppercase() {
            let mut depth = 0i32;
            let mut k = j;
            let mut close = b.len();
            while k < b.len() {
                match b[k] {
                    b'{' => depth += 1,
                    b'}' => {
                        depth -= 1;
                        if depth == 0 {
                            close = k;
                            break;
                        }
                    }
                    _ => {}
                }
                k += 1;
            }
            out.push(Element {
                name: name.to_string(),
                line: line_of(&src.text, start),
                open: j + 1,
                close,
            });
        }
    }
    out
}

/// The values of `prop:` (or `prop =`) that belong to the element itself, not
/// to an element or a function inside it.
fn own_values<'a>(src: &'a Source, e: &Element, prop: &str) -> Vec<&'a str> {
    let b = src.masked.as_bytes();
    let mut out = Vec::new();
    let mut depth = 0i32;
    let mut i = e.open;
    while i < e.close {
        match b[i] {
            b'{' => depth += 1,
            b'}' => depth -= 1,
            c if depth == 0
                && (c.is_ascii_alphabetic() || c == b'_')
                && (i == 0 || !is_name(b[i - 1])) =>
            {
                let start = i;
                while i < e.close && is_name(b[i]) {
                    i += 1;
                }
                if &src.masked[start..i] == prop {
                    let mut j = i;
                    while j < e.close && b[j].is_ascii_whitespace() {
                        j += 1;
                    }
                    if j < e.close && b[j] == b':' {
                        j += 1;
                        let from = j;
                        while j < e.close && !matches!(b[j], b'\n' | b';' | b'}') {
                            j += 1;
                        }
                        out.push(src.masked[from..j].trim());
                    }
                }
                continue;
            }
            _ => {}
        }
        i += 1;
    }
    out
}

// ---------------------------------------------------------------- the checks

/// Every violation of the plain-text rules in `src`; `rich` says how many
/// times each markup token is allowed in this file.
fn text_findings(src: &Source, rich: &[(&str, &str, usize, &str)]) -> Vec<String> {
    let mut out = Vec::new();
    for e in elements(src) {
        if TEXT_TYPES.contains(&e.base()) {
            let formats = own_values(src, &e, "textFormat");
            if !formats
                .iter()
                .any(|f| f.ends_with(".PlainText") || rich_ok(src, rich, f))
            {
                out.push(format!(
                    "{}:{}: `{}` without `textFormat: Text.PlainText` draws <b>, <a href> and <img> of \
                     its text as markup",
                    src.path, e.line, e.name
                ));
            }
        }
        if PLAIN_BY_DEFAULT.contains(&e.base()) {
            for f in own_values(src, &e, "textFormat") {
                if !f.ends_with(".PlainText") {
                    out.push(format!(
                        "{}:{}: `{}` is plain text unless told otherwise; this one is `{f}`",
                        src.path, e.line, e.name
                    ));
                }
            }
        }
    }
    // Any other `textFormat` that is not plain, in any form (a binding, an
    // assignment in a handler), and any markup name.
    let m = &src.masked;
    let mut at = 0;
    while let Some(p) = m[at..].find("textFormat") {
        let p = at + p;
        at = p + "textFormat".len();
        let before_ok = p == 0 || !is_name(m.as_bytes()[p - 1]) || m.as_bytes()[p - 1] == b'.';
        if !before_ok {
            continue;
        }
        let rest = m[at..].trim_start();
        if rest.starts_with(':') || (rest.starts_with('=') && !rest.starts_with("==")) {
            let value: String = rest[1..]
                .lines()
                .next()
                .unwrap_or("")
                .split([';', '}'])
                .next()
                .unwrap_or("")
                .trim()
                .to_string();
            if !value.ends_with(".PlainText") && !rich_ok(src, rich, &value) {
                out.push(format!(
                    "{}:{}: textFormat is `{value}`: text from outside is plain",
                    src.path,
                    line_of(&src.text, p)
                ));
            }
        }
    }
    for token in [
        "RichText",
        "StyledText",
        "MarkdownText",
        "AutoText",
        "Text.Markdown",
        "TextEdit.Markdown",
    ] {
        let count = m.matches(token).count();
        let allowed = rich
            .iter()
            .filter(|(f, t, _, _)| *f == src.path && *t == token)
            .map(|(_, _, n, _)| *n)
            .sum::<usize>();
        if count != allowed {
            out.push(format!(
                "{}: {count} x {token}, {allowed} allowed (RICH lists the components that draw \
                 markup, each with the reason it is safe)",
                src.path
            ));
        }
    }
    out
}

/// Whether `value` (a `textFormat`) is a markup this file is listed for.
fn rich_ok(src: &Source, rich: &[(&str, &str, usize, &str)], value: &str) -> bool {
    rich.iter()
        .any(|(f, token, _, _)| *f == src.path && value.ends_with(token))
}

/// Violations of the link rules in `src`.
fn link_findings(src: &Source, openers: &[(&str, &[&str], &str)], linkers: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    let m = &src.masked;
    for bad in ["Qt.openUrlExternally", "Qt.openUrl"] {
        if let Some(p) = m.find(bad) {
            out.push(format!(
                "{}:{}: {bad}: open a link with TelamonPortal.openUrl, which refuses what is not \
                 http, https, mailto or a safe local file",
                src.path,
                line_of(&src.text, p)
            ));
            break;
        }
    }
    // TelamonPortal.openUrl(<argument>)
    let mut at = 0;
    while let Some(p) = m[at..].find("openUrl(") {
        let p = at + p;
        at = p + "openUrl(".len();
        if m[..p].ends_with("Qt.") {
            continue;
        }
        let arg: String = text_of_call(&src.text, &src.masked, at);
        match openers.iter().find(|(f, _, _)| *f == src.path) {
            None => out.push(format!(
                "{}:{}: openUrl is called here; OPENERS lists the files that may, each with the URL \
                 it opens and why that URL is checked",
                src.path,
                line_of(&src.text, p)
            )),
            Some((_, args, _)) => {
                if !args.contains(&arg.trim()) {
                    out.push(format!(
                        "{}:{}: openUrl({arg}): not an argument OPENERS lists",
                        src.path,
                        line_of(&src.text, p)
                    ));
                }
            }
        }
    }
    for hook in ["linkActivated", "LinkActivated"] {
        if let Some(p) = m.find(hook)
            && !linkers.contains(&src.path.as_str())
        {
            out.push(format!(
                "{}:{}: {hook}: only components that forward the link to the app handle it",
                src.path,
                line_of(&src.text, p)
            ));
        }
    }
    out
}

/// The text of a call's first argument, from just after the `(`.
fn text_of_call(text: &str, masked: &str, from: usize) -> String {
    let b = masked.as_bytes();
    let mut depth = 0;
    let mut i = from;
    while i < b.len() {
        match b[i] {
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' if depth == 0 => break,
            b')' | b']' | b'}' => depth -= 1,
            b',' if depth == 0 => break,
            _ => {}
        }
        i += 1;
    }
    text[from..i].to_string()
}

/// Violations of the code and network rules in `src`.
fn code_findings(src: &Source) -> Vec<String> {
    let mut out = Vec::new();
    let m = &src.masked;
    let mut add = |p: usize, what: &str| {
        out.push(format!("{}:{}: {what}", src.path, line_of(&src.text, p)));
    };
    for bad in [
        "eval(",
        "new Function",
        "Function(",
        "Qt.include",
        "XMLHttpRequest",
        "fetch(",
        "WebSocket",
        "WebView",
        "WebEngine",
        "Qt.callLater(eval",
        "importScripts",
    ] {
        let mut at = 0;
        while let Some(p) = m[at..].find(bad) {
            let p = at + p;
            at = p + bad.len();
            let prev = if p == 0 { b' ' } else { m.as_bytes()[p - 1] };
            // `evaluate(` etc. are other names; `.Function(` is a method.
            if bad.ends_with('(') && (is_name(prev)) {
                continue;
            }
            add(
                p,
                &format!("{bad}: QML here neither runs text as code nor fetches"),
            );
        }
    }
    // Qt.createQmlObject / Qt.createComponent: a literal argument only.
    for call in ["Qt.createQmlObject(", "Qt.createComponent("] {
        let mut at = 0;
        while let Some(p) = m[at..].find(call) {
            let p = at + p;
            at = p + call.len();
            let arg = text_of_call(&src.text, m, at);
            let arg = arg.trim();
            let literal = arg.len() >= 2
                && (arg.starts_with('"') || arg.starts_with('\''))
                && arg.ends_with(arg.chars().next().unwrap())
                && !arg[1..arg.len() - 1].contains(arg.chars().next().unwrap())
                && !arg.contains('+');
            if !literal {
                add(
                    p,
                    &format!(
                        "{call}…): the argument is not a string literal, so text from outside could become code"
                    ),
                );
            }
        }
    }
    // A literal http: URL (cleartext) anywhere in a string.
    for (n, line) in src.text.lines().enumerate() {
        let t = line.trim_start();
        if t.starts_with("//") || t.starts_with('*') || t.starts_with("/*") {
            continue;
        }
        if line.contains("\"http://") || line.contains("'http://") {
            out.push(format!(
                "{}:{}: a cleartext http:// URL in a string",
                src.path,
                n + 1
            ));
        }
    }
    // A Loader whose `source` is a string loads whatever it names as QML.
    for e in elements(src) {
        if e.base() == "Loader"
            && !own_values(src, &e, "source").is_empty()
            && !LOADER_SOURCES.iter().any(|(f, _)| *f == src.path)
        {
            out.push(format!(
                "{}:{}: Loader with `source`: use sourceComponent, a string could name any QML",
                src.path, e.line
            ));
        }
    }
    out
}

/// Violations of the image rules: an `Image` is made only where `images`
/// says, with the checked source.
fn image_findings(src: &Source, images: &[(&str, &[&str], &str)]) -> Vec<String> {
    let mut out = Vec::new();
    for e in elements(src) {
        if !matches!(
            e.base(),
            "Image" | "AnimatedImage" | "BorderImage" | "AnimatedSprite"
        ) {
            continue;
        }
        let sources = own_values(src, &e, "source");
        match images.iter().find(|(f, _, _)| *f == src.path) {
            None => {
                // Only a literal qrc/relative file is fine anywhere.
                for s in &sources {
                    let lit = text_at(src, e.open, e.close, "source");
                    let ok = lit.starts_with('"') && !lit.contains("http");
                    if !ok {
                        out.push(format!(
                            "{}:{}: `{} {{ source: {s} }}`: a source from outside loads over the network \
                             or from any file; list the file in IMAGES with its check",
                            src.path, e.line, e.name
                        ));
                    }
                }
            }
            Some((_, wanted, _)) => {
                for s in &sources {
                    if !wanted.contains(&s.trim()) {
                        out.push(format!(
                            "{}:{}: `{}` source is `{s}`, IMAGES wants one of {wanted:?} (the checked one)",
                            src.path, e.line, e.name
                        ));
                    }
                }
            }
        }
    }
    out
}

/// The unmasked text of `prop:`'s first value in the element (for a literal).
fn text_at<'a>(src: &'a Source, open: usize, close: usize, prop: &str) -> &'a str {
    let body = &src.text[open..close];
    let Some(p) = body.find(&format!("{prop}:")) else {
        return "";
    };
    body[p + prop.len() + 1..]
        .lines()
        .next()
        .unwrap_or("")
        .trim()
}

/// Password fields made in `src` (outside TelamonPasswordField itself) must
/// say what empties them.
fn password_findings(src: &Source) -> Vec<String> {
    let mut out = Vec::new();
    if src.path == "ui/TelamonPasswordField.qml" {
        return out;
    }
    for e in elements(src) {
        if e.base() != "TelamonPasswordField" {
            continue;
        }
        // The gallery's demos show static states with sample text.
        if src.path.starts_with("ui/gallery/demos/") {
            continue;
        }
        let Some(id) = own_values(src, &e, "id").first().map(|s| s.to_string()) else {
            out.push(format!(
                "{}:{}: a password field needs an id, to be emptied",
                src.path, e.line
            ));
            continue;
        };
        let cleared = format!("{id}.text = \"\"");
        if !src.text.contains(&cleared) {
            out.push(format!(
                "{}:{}: `{cleared}` not found: the password must not stay in the field after it is used",
                src.path, e.line
            ));
        }
    }
    out
}

fn assert_clean(findings: Vec<String>) {
    assert!(findings.is_empty(), "\n{}\n", findings.join("\n"));
}

// ------------------------------------------------------------ the real files

#[test]
fn drawn_text_is_plain() {
    let mut findings = Vec::new();
    for src in sources() {
        if TEXT_PENDING.iter().any(|(f, _)| *f == src.path) {
            continue;
        }
        let rich: Vec<_> = RICH
            .iter()
            .copied()
            .filter(|(f, ..)| *f == src.path)
            .collect();
        findings.extend(text_findings(&src, &rich));
    }
    assert_clean(findings);
}

#[test]
fn rich_text_is_where_it_is_listed() {
    // Every entry of RICH is still true: the file exists and has the token as
    // many times as the list says (a removed use must leave the list).
    let all = sources();
    for (file, token, n, why) in RICH {
        let src = all
            .iter()
            .find(|s| s.path == *file)
            .unwrap_or_else(|| panic!("{file} on RICH does not exist any more"));
        assert_eq!(src.masked.matches(token).count(), *n, "{file}: {token}");
        assert!(why.len() > 40, "{file}: say why it is safe");
    }
}

#[test]
fn rich_text_users_stay_where_they_are() {
    // NotesText is the app's release notes: a gallery demo or the module may
    // use it only where listed here.
    let mut users = Vec::new();
    for src in sources() {
        for e in elements(&src) {
            if e.base() == "NotesText"
                && src.path != "ui/NotesText.qml"
                && !NOTES_USERS.iter().any(|(f, _)| *f == src.path)
            {
                users.push(src.path.clone());
            }
        }
    }
    assert!(
        users.is_empty(),
        "NotesText is used in {users:?}: its html must come from a sanitiser; add the file here \
         with the reason"
    );
}

#[test]
fn links_are_opened_in_known_places_only() {
    let mut findings = Vec::new();
    for src in sources() {
        findings.extend(link_findings(&src, OPENERS, &["ui/NotesText.qml"]));
    }
    assert_clean(findings);
}

#[test]
fn about_page_filters_the_links_it_opens() {
    let all = sources();
    let about = all
        .iter()
        .find(|s| s.path == "ui/TelamonAboutPage.qml")
        .unwrap();
    // `links` only keeps http, https and mailto (documented), and says so.
    assert!(
        about.text.contains("/^(https?|mailto):/i.test(url)"),
        "TelamonAboutPage._links must filter the scheme"
    );
    assert!(OPENERS.iter().all(|(_, _, why)| why.len() > 40));
}

#[test]
fn notes_text_only_forwards_links() {
    let all = sources();
    let notes = all.iter().find(|s| s.path == "ui/NotesText.qml").unwrap();
    assert!(
        notes
            .masked
            .contains("onLinkActivated: link => root.linkClicked(link)"),
        "NotesText must only forward the link to the app, which decides (isSafeLink)"
    );
    assert!(!notes.masked.contains("openUrl"));
}

#[test]
fn no_qml_runs_text_as_code_or_fetches() {
    let mut findings = Vec::new();
    for src in sources() {
        findings.extend(code_findings(&src));
    }
    assert_clean(findings);
}

#[test]
fn images_come_from_checked_sources() {
    let mut findings = Vec::new();
    let all = sources();
    for src in &all {
        findings.extend(image_findings(src, IMAGES));
    }
    assert_clean(findings);
    for (file, _, why) in IMAGES {
        assert!(all.iter().any(|s| s.path == *file), "{file} on IMAGES");
        assert!(why.len() > 40);
    }
}

#[test]
fn avatar_and_choice_card_vet_their_source() {
    // Both draw what the app gives them. The check is the same as the
    // carousel's: no cleartext, no remote picture unless asked.
    let all = sources();
    for file in ["ui/TelamonAvatar.qml", "ui/TelamonChoiceCard.qml"] {
        let src = all.iter().find(|s| s.path == file).unwrap();
        assert!(src.masked.contains("allowRemote"), "{file}: allowRemote");
        assert!(src.masked.contains("_safeSource"), "{file}: _safeSource");
        assert!(
            !src.masked.contains("source: root.source")
                && !src.masked.contains("source: control.source"),
            "{file}: the Image must read _safeSource, not source"
        );
    }
}

#[test]
fn password_fields_are_emptied() {
    let mut findings = Vec::new();
    for src in sources() {
        findings.extend(password_findings(&src));
    }
    assert_clean(findings);
}

// ------------------------------------------------- the checker checks itself

fn snippet(path: &str, text: &str) -> Source {
    Source {
        path: path.to_string(),
        masked: mask(text),
        text: text.to_string(),
    }
}

fn text_of(path: &str, text: &str) -> Vec<String> {
    text_findings(&snippet(path, text), &[])
}

#[test]
fn checker_accepts_plain_text() {
    for ok in [
        "Item { Text { text: a; textFormat: Text.PlainText } }",
        "Item {\n  QQC2.Label {\n    text: x\n    textFormat: Text.PlainText\n  }\n}",
        "Item {\n  contentItem: Text {\n    textFormat: Text.PlainText\n  }\n}",
        "Item { Kirigami.Heading { text: a; textFormat: Text.PlainText } }",
        "Item { TextEdit { textFormat: TextEdit.PlainText } }",
        // A comment and a string that mention markup are not markup.
        "Item { // RichText is not used\n Text { text: \"RichText\"; textFormat: Text.PlainText } }",
        "Item { TelamonLabel { text: a } }",
        // The nested element's format does not count for its parent, but its own does.
        "Item { Text { textFormat: Text.PlainText; Item { Text { textFormat: Text.PlainText } } } }",
    ] {
        assert_eq!(text_of("ui/X.qml", ok), Vec::<String>::new(), "{ok}");
    }
}

#[test]
fn checker_rejects_markup_text() {
    for (bad, what) in [
        ("Item { Text { text: a } }", "no textFormat"),
        ("Item { QQC2.Label { text: a } }", "no textFormat Label"),
        (
            "Item { Text { text: a; textFormat: Text.RichText } }",
            "RichText",
        ),
        (
            "Item { Text { text: a; textFormat: Text.StyledText } }",
            "StyledText",
        ),
        (
            "Item { Text { text: a; textFormat: Text.AutoText } }",
            "AutoText",
        ),
        (
            "Item { Text { text: a; textFormat: Text.MarkdownText } }",
            "MarkdownText",
        ),
        ("Item { Text { text: a; textFormat: fmt } }", "a variable"),
        (
            "Item { Text { textFormat: Text.PlainText; Item { Text { text: a } } } }",
            "the child has none",
        ),
        (
            "Item { Text { textFormat: Text.PlainText; Component.onCompleted: textFormat = Text.RichText } }",
            "assigned in a handler",
        ),
        (
            "Item { TelamonLabel { text: a; textFormat: Text.RichText } }",
            "TelamonLabel switched away",
        ),
        ("Item { TextEdit { text: a } }", "TextEdit without a format"),
        (
            "Item { Kirigami.Heading { text: a } }",
            "Heading without a format",
        ),
    ] {
        assert!(
            !text_of("ui/X.qml", bad).is_empty(),
            "must fail ({what}): {bad}"
        );
    }
}

#[test]
fn checker_allow_list_is_exact() {
    let rich = [("ui/R.qml", "RichText", 1usize, "why")];
    let one = snippet("ui/R.qml", "Text { textFormat: Text.RichText }");
    assert!(text_findings(&one, &rich).is_empty());
    // A second use in the same file is not listed.
    let two = snippet(
        "ui/R.qml",
        "Item { Text { textFormat: Text.RichText } Text { textFormat: Text.RichText } }",
    );
    assert!(!text_findings(&two, &rich).is_empty());
    // Another file is not allowed.
    let other = snippet("ui/Other.qml", "Text { textFormat: Text.RichText }");
    assert!(!text_findings(&other, &rich).is_empty());
    // Another token in the allowed file is not allowed.
    let styled = snippet("ui/R.qml", "Text { textFormat: Text.StyledText }");
    assert!(!text_findings(&styled, &rich).is_empty());
}

#[test]
fn checker_masks_strings_comments_and_regexes() {
    let m = mask("a // Text {\n/* Text { */ \"Text {\" '}' x.replace(/\"/g, \"y\") z");
    assert!(!m.contains("Text"), "{m}");
    assert_eq!(
        m.len(),
        "a // Text {\n/* Text { */ \"Text {\" '}' x.replace(/\"/g, \"y\") z".len()
    );
    // A regular expression with a quote must not swallow the code after it.
    let src = snippet(
        "ui/X.qml",
        "Item { function f(s) { return s.replace(/\"/g, \"\"); } Text { text: a } }",
    );
    assert_eq!(text_findings(&src, &[]).len(), 1);
    // Division is not a regular expression.
    let src = snippet(
        "ui/X.qml",
        "Item { width: a / 2; Text { text: \"x\"; textFormat: Text.PlainText } }",
    );
    assert!(text_findings(&src, &[]).is_empty());
}

fn links_of(path: &str, text: &str) -> Vec<String> {
    link_findings(&snippet(path, text), OPENERS, &["ui/NotesText.qml"])
}

#[test]
fn checker_links() {
    assert!(links_of("ui/X.qml", "Item { onClicked: Qt.openUrlExternally(u) }").len() == 1);
    assert!(links_of("ui/X.qml", "Item { onClicked: Qt.openUrl(u) }").len() == 1);
    assert!(links_of("ui/X.qml", "Item { onClicked: TelamonPortal.openUrl(u) }").len() == 1);
    assert!(links_of("ui/X.qml", "Text { onLinkActivated: l => go(l) }").len() == 1);
    // The listed file, the listed argument.
    assert!(
        links_of(
            "ui/TelamonAboutPage.qml",
            "Item { onClicked: TelamonPortal.openUrl(TelamonApp.sourceUrl) }"
        )
        .is_empty()
    );
    // The listed file, another argument.
    assert!(
        links_of(
            "ui/TelamonAboutPage.qml",
            "Item { onClicked: TelamonPortal.openUrl(model.anything) }"
        )
        .len()
            == 1
    );
    assert!(
        links_of(
            "ui/TelamonAboutPage.qml",
            "Item { onClicked: Qt.openUrlExternally(TelamonApp.sourceUrl) }"
        )
        .len()
            == 1
    );
    // The forwarding component.
    assert!(links_of("ui/NotesText.qml", "Text { onLinkActivated: l => s(l) }").is_empty());
    // A comment is not a call.
    assert!(links_of("ui/X.qml", "Item { // Qt.openUrlExternally(u)\n }").is_empty());
}

#[test]
fn checker_code_and_network() {
    for bad in [
        "Item { Component.onCompleted: eval(s) }",
        "Item { Component.onCompleted: new Function(s)() }",
        "Item { Component.onCompleted: Qt.include(s) }",
        "Item { Component.onCompleted: Qt.createQmlObject(s, this) }",
        "Item { Component.onCompleted: Qt.createQmlObject(\"Item {\" + s + \"}\", this) }",
        "Item { Component.onCompleted: Qt.createComponent(url) }",
        "Item { Component.onCompleted: { var x = new XMLHttpRequest(); } }",
        "Item { Component.onCompleted: fetch(u) }",
        "Item { WebSocket { } }",
        "Item { property string u: \"http://example.com/a.png\" }",
        "Item { Loader { source: page } }",
    ] {
        assert!(
            !code_findings(&snippet("ui/X.qml", bad)).is_empty(),
            "{bad}"
        );
    }
    for ok in [
        "Item { Component.onCompleted: Qt.createQmlObject(\"import QtQuick\\nItem {}\", this) }",
        "Item { Component.onCompleted: Qt.createComponent(\"Foo.qml\") }",
        "Item { // eval(x) is not used\n property string s: \"fetch(\" }",
        "Item { function retrieval() {} property var v: evaluate(1) }",
        "Item { property string u: \"https://example.com\"; Loader { sourceComponent: c } }",
    ] {
        assert_eq!(
            code_findings(&snippet("ui/X.qml", ok)),
            Vec::<String>::new(),
            "{ok}"
        );
    }
}

#[test]
fn checker_images() {
    let images = IMAGES;
    let f = |path: &str, text: &str| image_findings(&snippet(path, text), images);
    // A literal local file is fine anywhere.
    assert!(f("ui/X.qml", "Item { Image { source: \"qrc:/a.png\" } }").is_empty());
    // A literal remote file, or a variable, is not.
    assert!(!f("ui/X.qml", "Item { Image { source: \"https://a/b.png\" } }").is_empty());
    assert!(!f("ui/X.qml", "Item { Image { source: model.url } }").is_empty());
    assert!(!f("ui/X.qml", "Item { AnimatedImage { source: model.url } }").is_empty());
    // Listed: only the checked source.
    assert!(
        f(
            "ui/TelamonAvatar.qml",
            "Item { Image { source: root._safeSource } }"
        )
        .is_empty()
    );
    assert!(
        !f(
            "ui/TelamonAvatar.qml",
            "Item { Image { source: root.source } }"
        )
        .is_empty()
    );
}

#[test]
fn checker_password_fields() {
    let pw = |path: &str, text: &str| password_findings(&snippet(path, text));
    assert!(!pw("ui/Page.qml", "Item { TelamonPasswordField { } }").is_empty());
    assert!(!pw("ui/Page.qml", "Item { TelamonPasswordField { id: p } }").is_empty());
    assert!(
        pw(
            "ui/Page.qml",
            "Item { TelamonPasswordField { id: p } onClosed: p.text = \"\" }"
        )
        .is_empty()
    );
    // The demos show states with sample text.
    assert!(
        pw(
            "ui/gallery/demos/XDemo.qml",
            "Item { TelamonPasswordField { text: \"abc\" } }"
        )
        .is_empty()
    );
}

#[test]
fn checker_finds_the_real_files() {
    // If the walk found no Text at all, every rule above would pass
    // for nothing.
    let all = sources();
    let texts: usize = all
        .iter()
        .map(|s| {
            elements(s)
                .iter()
                .filter(|e| TEXT_TYPES.contains(&e.base()))
                .count()
        })
        .sum();
    assert!(texts > 150, "found only {texts} Text elements");
    let opens: usize = all
        .iter()
        .map(|s| s.masked.matches("openUrl(").count())
        .sum();
    assert!(opens >= 3, "found only {opens} openUrl calls");
    assert!(
        all.iter().any(|s| s.path == "ui/gallery/Main.qml"),
        "the gallery is read"
    );
    assert!(
        all.iter().any(|s| s.path.starts_with("template/")),
        "the template is read"
    );
}
