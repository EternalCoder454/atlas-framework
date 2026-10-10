---
title: TelamonConsoleView
summary: Read-only monospace view for the streaming output of a command, with ANSI colours drawn in the theme's colours, bounded scrollback and follow-tail.
section: Text and code
since: "2.1.0"
---

TelamonConsoleView shows the output of a command as it arrives: `append()` adds text at the end, in chunks of any size (a chunk may cut an escape sequence, a line break or a character in two). The text is selectable (mouse, Ctrl+A, Ctrl+C) and plain: nothing in it is taken as HTML or Markdown, no escape sequence is run, and nothing in the output is ever made a link, opened or fetched. The colours and text styles of ANSI escape sequences are drawn in the theme's colours; every other escape sequence is dropped.

The view keeps the last `maximumLines` lines. While `follow` is on and the view is at the end, it stays there as output comes in; scrolling up stops that, and scrolling back to the end (or `scrollToEnd()`) goes on. For a fixed piece of text (a command, a snippet) use [TelamonCodeView](telamon-code-view.md).

## Example

```qml
TelamonConsoleView {
    id: console
    Layout.fillWidth: true
    Layout.fillHeight: true
    maximumLines: 5000
}

Process {
    onReadyReadStandardOutput: console.append(readAllStandardOutput())
}
Button { text: "Clear"; onClicked: console.clear() }
```

## What is shown and what is dropped

**Text styles and colours (SGR, `ESC [ ... m`).** Parameters can be separated by `;` or `:`; an empty parameter is 0.

| Code | Effect |
|---|---|
| `0` | Reset every style and colour |
| `1`, `22` | Bold on; bold and dim off |
| `2` | Dim (the colour moves toward the surface) |
| `3`, `23` | Italic on, off |
| `4`, `24` | Underline on, off (`4:0` is off, `4:1` to `4:5` are on) |
| `7`, `27` | Inverse on, off |
| `9`, `29` | Strike-through on, off |
| `30`-`37`, `90`-`97` | Foreground: the 8 colours and their bright variants |
| `40`-`47`, `100`-`107` | Background: the same colours |
| `39`, `49` | Default foreground, default background |
| `38;5;n`, `48;5;n` | 256-colour foreground, background (also `38:5:n`) |
| `38;2;r;g;b`, `48;2;r;g;b` | Truecolour foreground, background (also `38:2:r:g:b` and `38:2::r:g:b`) |

Any other number is ignored without breaking the rest of the sequence (blink, conceal, double underline, overline and the underline colour `58` included). A sequence with more than 32 parameters uses the first 32; a number above 65535, a 256-colour index above 255 or a colour value above 255 makes that setting ignored. The style stays until `0` resets it, also across lines and calls; `clear()` resets it.

**Colours are the theme's, never the program's.** A colour is a slot of a palette of 16 theme colours: black is the muted text colour, red `TelamonStyle.error`, green `TelamonStyle.success`, yellow `TelamonStyle.warning`, blue `Kirigami.Theme.linkColor`, magenta `TelamonStyle.accentStrong`, cyan a mix of blue and green, white the text colour; the bright variants are the same colours moved 30 % toward the text colour. Every colour is moved toward the text colour until it has a contrast of 4.5:1 or more on the code surface. The 256 and truecolour values are approximated: indexes 0 to 15 are the palette; the rest (the 6x6x6 cube, the grey ramp, truecolour) become a grey from a ramp between the muted text colour and the text colour when they have little colour, and otherwise the nearest of the six hues (red, yellow, green, cyan, blue, magenta) by hue angle, in its bright variant when light. A background colour is a tint of the colour over the surface, and the text on it is kept legible. Inverse swaps the two, legibly.

**High contrast.** With `TelamonStyle.highContrast` on there is no colour at all: the text stays the text colour. Bold, italic, underline and strike-through keep their meaning, and inverse is shown as bold and underlined.

**Escape sequences that are dropped** (they have no effect, and the text around them stays):

- CSI (`ESC [` or U+009B) with any final byte other than `m`: cursor movement, erase, scroll regions, mode set and reset (`?25l`, `?1049h`), device reports; and CSI with a private marker (`<`, `=`, `>`, `?`) or intermediate bytes, also when its final byte is `m`.
- A malformed CSI, ended early by a control character, `ESC` or another byte that is not part of a sequence: the part so far is dropped and the byte that ended it is handled normally. One with more than 64 parameter bytes is dropped whole.
- OSC (`ESC ]` or U+009D) up to BEL or ST (`ESC \` or U+009C): window titles, hyperlinks (OSC 8, never made clickable), clipboard writes (OSC 52) and the rest. DCS, SOS, PM and APC (`ESC P`, `ESC X`, `ESC ^`, `ESC _`, or U+0090, U+0098, U+009E, U+009F) up to ST. An `ESC` inside such a string that does not start ST ends the string and starts a new sequence. A string that never ends is given up after 4096 characters and the text after goes on as normal text.
- Character set selection (`ESC ( B`, `ESC ) 0`) and every two-character escape (`ESC c`, `ESC 7`, `ESC =`).
- The other C1 controls U+0080 to U+009F.

**Control characters.**

- `\n` ends a line, and so do U+2028 and U+2029. `\r\n` is one line break, also when the two arrive in different `append()` calls.
- A lone `\r` (a progress bar) makes the next character that is shown replace the content of the last line; only the last line is touched. Output that ends in `\r` leaves the line as it is until more text comes.
- Tab is kept (a tab stop every 8 characters). BEL, backspace, vertical tab, form feed, NUL, DEL and every other control character are dropped: no bell, no cursor movement.
- Bidirectional controls (U+061C, U+200E, U+200F, U+202A to U+202E, U+2066 to U+2069) and U+FEFF, U+200B, U+200C, U+200D are dropped, and so are the other invisible format characters (U+00AD, U+034F, U+180E, U+2060 to U+2064, U+206A to U+206F, U+FFF9 to U+FFFC, the tag characters U+E0001 and U+E0020 to U+E007F) and U+FDD0 and U+FDD1, so output cannot reorder or hide text. A lone surrogate becomes U+FFFD; half a surrogate pair at the end of a call waits for the next one.

Other Unicode text passes through unchanged. A line is cut after 4096 UTF-16 units and the rest goes on in a new line (a character is not cut in two), so one huge line cannot slow the view. A line keeps its first 256 changes of style; the rest of it is drawn in the plain style.

## Scrollback

After every `append()` the view holds at most `maximumLines` lines: the oldest go first, whole lines. A line is counted when it has text; the empty line after a final newline is not. One `append()` of 100,000 lines puts only the last `maximumLines` of them in the view. When the view is not following and lines go from the top, it moves up with them so that what it shows stays in place.

## Accessibility

Screen readers get the text field, named "Console output", read-only. Set `Accessible.name` on the view to say whose output it is ("Build output").

## Keyboard

| Key | Action |
|---|---|
| `Ctrl+A` | Select all |
| `Ctrl+C` | Copy the selection as plain text |
| `Up`, `Down` | Scroll one line |
| `Page Up`, `Page Down` | Scroll one page |
| `Ctrl+Home`, `Ctrl+End` | Scroll to the start, to the end (and follow again) |
| `Left`, `Right`, `Home`, `End` | Scroll sideways |
| `Shift` with the arrow keys | Extend the selection |

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `follow` | `bool` | `true` | Keeps the view at the end while output comes in. Turning it on scrolls to the end. |
| `following` | `bool` | | Read-only. True while `follow` is on and the view is at the end. It turns false when the user scrolls up and true again at the end. |
| `framed` | `bool` | `true` | Draws a card around the text. |
| `inset` | `bool` | `false` | Gives an unframed view the same leading and trailing room as the text of a `SectionRow`. See [TelamonCodeView](telamon-code-view.md#properties). |
| `lineCount` | `int` | `0` | Read-only. The lines held. |
| `maximumLines` | `int` | `10000` | The most lines kept. Less than 1 is 1 and more than 100,000,000 is 100,000,000; a lower value drops the oldest lines at once. |
| `selectedText` | `string` | `""` | Read-only. The selected text, plain. |
| `wrap` | `bool` | `false` | Wraps long lines instead of scrolling sideways. |

## Methods

| Name | Description |
|---|---|
| `append(text)` | Adds `text` at the end. Chunks may split an escape sequence, `\r\n` or a surrogate pair; the view keeps the state between calls. |
| `clear()` | Empties the view and forgets the colour state and any unfinished escape sequence. The view follows again. |
| `copy()` | Copies the selection to the clipboard as plain text. Does nothing without a selection. |
| `plainText()` | The whole text the view holds, without colours. A method, so no copy is made per `append()`. |
| `scrollToEnd()` | Scrolls to the end. With `follow` on the view follows again. |
| `selectAll()` | Selects all the text. |

The view is an `Item`; inherited members are those of [Item](https://doc.qt.io/qt-6/qml-qtquick-item.html).
