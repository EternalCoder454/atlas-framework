# Atlas.Ui 1.5.0: API sketch

This is the design of every new Atlas.Ui 1.5.0 API, written before any of it is
built. It covers ROADMAP "1.5.0", sections A1 and B1, and one framework-wide
rule for B2's "internal assignments break app bindings". It has no code to
ship: the QML below shows the shape of each design, not the final source.

Every item is additive (see "Compatibility" in DESIGN.md). Nothing is renamed,
removed or given a new meaning, with one stated exception: InfoBanner (item 18).
Each new member gets its line in `api/atlas-ui.api` and its row on its
`docs/reference` page in the commit that builds it. No new type is proposed,
so no app `.qml` file can be hidden. The names `AtlasBusyRow`, `PageBusy`,
`SidebarFooter` and `AtlasMenuModel` were checked in all Atlas app folders and
none exists, in case a later design needs one.

## How to read this

Each item has the members (`name: type = default`), the behaviour, how it fits
the existing API, and open questions. The "Common rules" below apply to every
item and are not repeated; an item names only what is special.

## Common rules

- **Keyboard.** Every new control or part that does something is reachable
  with Tab (or is a documented non-stop, such as a chevron whose action the
  keyboard has another way to reach), shows the focus ring and has an
  accessible name and role.
- **RTL.** Leading and trailing, `start` and `end`: never left and right.
  Under `LayoutMirroring` they flip. Chevrons and arrows flip with them.
- **Text at 200 %.** Sizes come from `Kirigami.Units` and `AtlasStyle`. Text
  that can grow elides or wraps, never clips a button. A new row has a
  `Layout.minimumHeight`, not a fixed one.
- **Compact.** Only the sidebar, the page and the dialogs have a compact form.
  Where an item has one it is stated.
- **Reduced motion.** New motion uses `AtlasStyle.duration*`, which is 0 under
  `reducedMotion`. A spring checks `AtlasStyle.reducedMotion` as the sidebar
  highlight does. The end state must be right with no animation.
- **High contrast.** Borders use `AtlasStyle.separator` or `controlBorder`,
  never an alpha below what those give. A "dimmed" or "quiet" state is full
  strength under `AtlasStyle.highContrast`.
- **Idle cost.** No new timer or animation runs while nothing changes.
- **Demos and tests.** Each item below gets a demo state (or a new demo for a
  new member), a test that fails without it, and goldens that are looked at.

## Part 1. User edits and app bindings (B2)

### The problem

A control that the user edits writes its own public property. In QML any write
ends a binding on that property. After the first click the app's
`value: model.rating` is gone and the control no longer follows the app. This
happens in AtlasRating, AtlasSegmentedControl, AtlasCalendar, AtlasComboBox,
AtlasColorField, AtlasDatePicker, AtlasFontPicker, AtlasFileField,
AtlasFolderField, FindBar (three toggles) and AtlasSidebar (`filterText`).

Apps read the property in the handler and react to its `onXChanged`. Notepad
does both: `FindBar.onMatchCaseChanged` and `findBar.matchCase`, and
`picker.font.family` inside `AtlasFontPicker.onEdited`. So the property must
still show the new value at once, and its change signal must still fire. A
design that only emits a signal and leaves the property alone would break
those apps silently.

### The rule

A user edit is held by the control with a `Binding` that targets the public
property and is active for one turn of the event loop.

1. The control never writes a public property it exposes for apps to bind.
   (The one exception is correcting an invalid value the app set, which is
   already documented, such as `AtlasTimePicker.hours` being clamped.)
2. A user edit stores the new value in a private `_edit` property and sets
   `_editing`. An internal `Binding` with `when: _editing` and
   `restoreMode: Binding.RestoreBinding` then drives the public property.
   From that moment `value` is the new value, `onValueChanged` fires and the
   control's own signal is emitted, so every reader and handler sees the
   edit, exactly as today.
3. The edit signal is emitted. The app may update its own source inside the
   handler.
4. One turn later (`Qt.callLater`) `_editing` is cleared and the Binding lets
   go. QML then restores the app's binding if there was one, which evaluates
   to the new value when the app took the edit, and to the old value when the
   app refused it (a controlled control springs back). With no app binding
   the property keeps the edited value.
5. A property that is written by a nested control (the popup calendar inside
   AtlasDatePicker, the toggles inside FindBar) is held the same way, and the
   inner-to-outer link is a `Binding` as in AtlasDatePicker's `_sync` today.
6. For a grouped value such as `font`, the Binding targets the sub-properties
   (`property: "font.family"`), because an app binds `font.family`, not
   `font`.

What an app can rely on, to go on the reference pages once:

| App code | Result after a user edit |
|---|---|
| `value: model.x` and the handler stores the edit in `model.x` | follows the model, binding intact |
| `value: model.x` and the handler ignores the edit | springs back to `model.x` after the handler |
| `value: 3`, or nothing, and the app reads `value` in the handler | shows and reports the edit, as 1.4.0 |
| `onValueChanged: ...` | fires with the edited value, as 1.4.0 |

No existing signal, property or its meaning changes, so `tools/check-api.sh`
sees no changed line.

### Shown on AtlasRating

```qml
T.Control {
    id: control
    property real value: 0
    signal edited

    property real _edit: 0
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "value"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }
    function _release(): void { control._editing = false }

    function _set(v) {
        const next = Math.max(0, Math.min(_stars, v));
        if (next === _rounded) return;
        _edit = next;
        _editing = true;      // value is `next` from here
        edited();             // the app may take it into its own source
        Qt.callLater(_release);
    }
}
```

### Shown on AtlasSegmentedControl

```qml
T.Control {
    id: control
    property int currentIndex: 0
    signal activated(int index)

    property int _edit: 0
    property bool _editing: false
    readonly property Binding _hold: Binding {
        target: control
        property: "currentIndex"
        value: control._edit
        when: control._editing
        restoreMode: Binding.RestoreBinding
    }

    function _choose(i) {
        if (i < 0 || i >= count || i === currentIndex) return;
        _edit = i;
        _editing = true;
        activated(i);
        Qt.callLater(() => control._editing = false);
    }
}
```

The segment highlight spring reads `currentIndex`, so it still moves on the
edit and, if the app refuses, moves back; both follow reduced motion as now.

### Where it applies

| Control | Property held | Edit signal (unchanged) |
|---|---|---|
| AtlasRating | `value` | `edited()` |
| AtlasSegmentedControl | `currentIndex` | `activated(index)` |
| AtlasCalendar | `selectedDate`, `month`, `year` | `activated(date)` |
| AtlasComboBox | `currentIndex` (and the typed filter text) | `activated(index)` |
| AtlasColorField | `color` | `edited()` |
| AtlasDatePicker | `selectedDate` | `edited()` |
| AtlasFontPicker | `font.family`, `font.pointSize`, `font.styleName` | `edited()` |
| AtlasFileField, AtlasFolderField | `path` | `edited()` |
| FindBar | `matchCase`, `wholeWords`, `regularExpression`, `findText`, `replaceText` | none (apps use `onXChanged`) |
| AtlasSidebar | `filterText` (typed in the built-in search field) | none (`onFilterTextChanged`) |

Each control also gets a test with the three app styles in the table above.

### Open questions for the rule

- **Verify before building (blocking).** The rule depends on how Qt 6.11's
  `Binding` with `restoreMode: RestoreBinding` treats the target: that it
  keeps an existing app binding aside and restores it, and that with no app
  binding it keeps the last value. The first task of the F phase is a
  prototype with the three app styles above. If Qt behaves differently, the
  fallback is: the control keeps a private mirror `_x` fed by
  `Binding { restoreMode: Binding.RestoreNone }` (the AtlasDatePicker `_sync`
  pattern), the edit signal carries the new value as a trailing argument
  (changing signal lines in `api/`), and `onXChanged` no longer fires for user
  edits. That breaks Notepad's FindBar and FontPicker handlers, which would
  have to move first.
- Flicker: a bound value the app refuses shows the edit for one turn. Accept?

## Part 2. Items by type

Items are numbered once and in the order of the sections. Where a type has
several, they follow ROADMAP order.

### AtlasPopover

#### 1. A side: below, above, start, end (Notepad)

| Name | Type | Default | Description |
|---|---|---|---|
| `side` | `int` (`AtlasPopover.Side`) | `AtlasPopover.Auto` | Where the popover opens. |
| `placedSide` | `int` (read-only) | n/a | The side in use after fitting. |

Enum `AtlasPopover.Side`: `Auto = 0`, `Below = 1`, `Above = 2`, `Start = 3`,
`End = 4`. `Auto` is today's behaviour: below, else above.

Behaviour:

- `Start` and `End` are logical: `End` is the right of the target in LTR and
  the left in RTL. A popover on `Start` or `End` is centred on the target
  vertically and then clamped into the window.
- The arrow sits on the edge that faces the target and points at the centre of
  the target, kept off the rounded corners as the vertical arrow is now.
- If the chosen side has no room the popover flips to the opposite side. If
  neither fits it takes the side with more room and clamps. `placedSide`
  reports the result.
- The enter and exit fade is unchanged. Focus returns to the target on close,
  as now.

Fit: `above` stays and is true when `placedSide === Above`. `showArrow` is
unchanged. `Auto` keeps every existing popover exactly as it is, so no golden
of an existing demo changes.

### AtlasHeaderBar

#### 2. A stretch slot (Notepad)

| Name | Type | Default | Description |
|---|---|---|---|
| `stretch` | `list<QtObject>` (default-less alias) | empty | Items in a row that takes all the free width between the title and `actions` on one side and `trailing` on the other. |
| `showTitle` | `bool` | `true` | False leaves the title out, for a bar whose stretch row is the title. |

Behaviour:

- Order is: window menu button, `leading`, title, `actions`, `stretch`,
  `trailing`, window buttons. The stretch row is a `RowLayout`: a child that
  sets `Layout.fillWidth` takes the rest, so a `TabBar` fills the bar.
- Empty parts of the stretch row still drag the window and still maximise on
  double click, because the row is not a drag target. Items in it keep their
  clicks.
- With no free width the row is 0 wide and its items are hidden (not
  overlapped).
- The existing rule that `leading` and `trailing` each get at most half the
  bar (minus 13 px) is already in 1.4.0 and stays. It is not a new item.
- `titleCentered` is false while `stretch` has items.
- `AtlasWindow`'s top resize handle (`_freeStart`, `_freeEnd`) is unchanged.

### AtlasDialog

#### 3. Scroll to the top (Monitor)

| Name | Type | Default | Description |
|---|---|---|---|
| `scrollToTop()` | method | n/a | Moves the body to its top, with no animation. |

Behaviour: the Flickable stays private; the method is enough (a public
Flickable would freeze the internal layout as API). The dialog also scrolls to
the top by itself each time it opens, so a reopened dialog does not keep the
last scroll. Focus is not moved by the method.

Open question: is scroll-to-top on open acceptable as a fix? An app that
reopens a dialog at the same place on purpose would lose that. No app is known
to do it.

### AtlasPage

#### 4. A subtitle (Monitor)

| Name | Type | Default | Description |
|---|---|---|---|
| `subtitle` | `string` | `""` | One or two muted lines under the title. Hidden when empty. |

Behaviour: plain text (`textFormat: Text.PlainText`), wraps, up to three lines
and then elides, uses `AtlasStyle.textMuted`. The title stays the only
heading for screen readers; the subtitle is read as the page's description.
It stays under the title at 200 % and in RTL, where it aligns to the leading
edge. `headerTrailing` stays at the title row's end.

#### 5. A page-level busy row (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `busy` | `bool` | `false` | Shows a row with a spinner and `busyText` under the title row. |
| `busyText` | `string` | `""` | The label beside the spinner. |

Behaviour: no new type, so no name can collide. The row is an `AtlasSpinner`
and a muted label above the page content, in the same width as the content. It
slides in and out with `AtlasStyle.duration` and takes no space when `busy` is
false. Becoming busy announces `busyText` to screen readers once
(`Accessible.announce`), and the spinner carries its own `Indicator` role. A
busy page does not disable its content: the app does that where it needs to.
Under reduced motion the spinner uses its static form (`AtlasSpinner.animated`
off) and the row appears at once.

Fit: `SectionRow.busy` is unchanged and still covers one row. The same two
members also appear on `AtlasAboutPage`, which is an `AtlasPage`.

### AtlasSidebar and SidebarGroup

#### 6. A pinned footer (Monitor and Updater, one design)

Monitor asked for Settings and About, Updater for Settings, Crash Reports and
About. One API covers both.

| Name | Type | Default | Description |
|---|---|---|---|
| `footer` | `list<QtObject>` (alias) | empty | `SidebarItem` and `SidebarGroup` entries pinned under the scrolling list. |
| `footerSeparator` | `bool` | `true` | A hairline above the footer. |

`footer` is not the default property: the existing default stays the list.

Behaviour:

- The footer does not scroll. It takes its natural height, up to half of the
  sidebar; beyond that it scrolls inside its own region. The list gets the
  rest and keeps its scroll bar.
- It shares `compact` with the list: footer entries are scanned with the rest,
  so `compact`, `density`, the compact tooltip and `badge` work as they do.
- `currentIndex` counts the list's `SidebarItem`s first, then the footer's.
  Existing indexes do not move.
- One selection: at most one entry is selected across both regions. The
  highlight springs within a region. Between regions the old one fades out
  and the new one in with `AtlasStyle.durationShort`; under reduced motion it
  just swaps.
- Focus order is list then footer. Tab still enters at the selected entry,
  wherever it is. An entry gaining focus is scrolled into view in its region.
- `filterText` and the filter field apply to the list only. A footer entry
  never hides, and "No matches" counts only the list. Open question below.
- `contextMenuRequested` and `dropped` work for footer entries too (the same
  hit test).
- RTL and 200 %: the footer follows the list. High contrast: the separator is
  `AtlasStyle.separator`.

Open questions: should `dropEnabled` skip the footer by default (a "Settings"
entry is an odd drop target)? Recommendation: no change; apps ignore the drop
in `onDropped`.

#### 7. A symbol and a badge on SidebarGroup (study 3)

| Name | Type | Default | Description |
|---|---|---|---|
| `symbol` | `int` | `0` | A Material Symbol for the header, like `SidebarItem.symbol`. It wins over `iconName`. |
| `badge` | `string` | `""` | An icon name flagging the group, like `SidebarItem.badge`. |
| `badgeText` | `string` | `""` | What the badge means, for screen readers and the compact tooltip. |

All three are aliases of the header's own properties. The symbol fills while
the header is selected (a folded group that holds the selection) as
`SidebarItem` does. In compact mode the header is the icon alone and the badge
sits on its corner. `holdsSelection` is unchanged.

### ToolbarButton and AtlasToolbar

#### 8. Round, tip side and tooltip text on ToolbarButton (Notepad)

| Name | Type | Default | Description |
|---|---|---|---|
| `round` | `bool` | `false` | A circle: width equals height and the corner radius is half. |
| `tipSide` | `int` (`ToolbarButton.TipSide`) | `ToolbarButton.Below` | Where the tooltip opens. |
| `toolTipText` | `string` | `""` | The tooltip's name part, in place of the action's or the button's text. |
| `focusOnClick` | `bool` | `true` | With `focusable`, false makes the button a Tab stop that a click does not focus. |

Enum `ToolbarButton.TipSide`: `Below = 0`, `Start = 1`, `End = 2`.

Behaviour:

- `round` changes the shape only. The hover, press and checked layers, and the
  focus ring, follow the circle.
- `Below` is today's tooltip. `Start` and `End` open beside the button,
  flipping to the other side when there is no room, and under RTL swap.
  They use `AtlasToolTip` placed beside the button, with the same delay, and
  show for hover and for keyboard focus.
- `toolTipText` changes the tooltip name only. `Accessible.name` stays the
  action's or `text`, so a long tip does not become the spoken name. The
  shortcut still appends: "Bold (Ctrl+B)".
- `focusOnClick: false` with `focusable: true` sets `focusPolicy` to
  `Qt.TabFocus`. With `focusable: false` it has no effect.

Dropped as already possible: "multi-key shortcuts". `shortcutText` is free
text, so `shortcutText: "Ctrl+K, Ctrl+C"` already shows a chord.

Open question: `toolTipText` is small; keep it, or drop it because an action's
`toolTip` covers the action case? It is only needed for a button without an
action. Recommendation: keep.

#### 9. Orientation, overflow mode and click focus on AtlasToolbar

These support item 10; the toolbar is the part that does the work.

| Name | Type | Default | Description |
|---|---|---|---|
| `orientation` | `int` (`Qt.Horizontal` or `Qt.Vertical`) | `Qt.Horizontal` | The direction of the strip. |
| `overflow` | `int` (`AtlasToolbar.Overflow`) | `AtlasToolbar.Menu` | What happens to buttons that do not fit. |
| `focusOnClick` | `bool` | `true` | Passed to every button. |
| `scrolls` | `bool` (read-only) | n/a | True while `Scroll` mode has buttons out of view. |

Enum `AtlasToolbar.Overflow`: `Menu = 0` (today), `Scroll = 1`.

Behaviour:

- `Vertical` lays buttons top to bottom. `leading` is at the top, `trailing`
  at the bottom, the "more" button last. The fit uses the height. Dividers
  are horizontal lines. RTL does not change a vertical strip.
- `Scroll` shows whole buttons, one button per step, with a chevron in room
  kept at each end (shown only while there is more in that direction).
  Dividers are left out while it scrolls, because a step is one button. The
  mouse wheel steps one button per notch (partial turns of a touchpad are
  added up), and the chevrons are mouse targets with names ("Scroll back",
  "Scroll forward") and are not Tab stops: Tab moves through the buttons and
  the strip follows the focus. The step is instant under reduced motion and
  `AtlasStyle.durationShort` otherwise.
- Scroll mode's "more" menu is not shown. A button that is out of view is
  still reachable by Tab.

### AtlasFloatingToolbar

#### 10. Replace Notepad's ToolCapsule (Notepad)

New members, all forwarded to the inner `AtlasToolbar` where they apply:

| Name | Type | Default | Description |
|---|---|---|---|
| `orientation` | `int` | `Qt.Horizontal` | Vertical makes a tall capsule. See item 9. |
| `overflow` | `int` (`AtlasToolbar.Overflow`) | `AtlasToolbar.Menu` | See item 9. |
| `focusOnClick` | `bool` | `true` | See item 8. Notepad sets false. |
| `autoDim` | `bool` | `false` | Quiet until the pointer is near. |
| `dimOpacity` | `real` | `0.35` | The opacity while quiet. |
| `nearDistance` | `real` | `80` | How close the pointer must be, in px, to bring it to full. |
| `keepActive` | `bool` | `false` | Holds full strength, for an app popover the toolbar cannot see. |
| `near` | `bool` (read-only) | n/a | True at full strength. |
| `returnFocus` | `Item` | `null` | Where Escape sends the focus. |
| `escaped()` | signal | n/a | Escape was pressed on a button. |

Behaviour:

- **Shape.** Vertical makes the capsule `width` by `height` swapped. The pill
  radius is half of the shorter side. The slide that comes with `shown` goes
  sideways for a vertical bar, away from the edge nearest it.
- **Dimming.** With `autoDim`, the opacity is `dimOpacity` until the pointer
  is within `nearDistance` of the capsule's rectangle, even outside it. It is
  full while: a button has focus, any menu or popover opened from the strip
  is open, `keepActive` is true, or a press is down (a tap on a touch screen
  has no hover). It is always 1 under high contrast and with `autoDim` off.
  The change fades with `AtlasStyle.duration` (instant under reduced motion).
  The pointer is read with one `HoverHandler` on the parent: no timer, so
  nothing runs while the pointer is still. Hidden (`shown: false`) it tracks
  nothing.
- **Keyboard.** With `focusable`, Tab enters the strip and moves through the
  buttons. Escape on a button emits `escaped()` and moves the focus to
  `returnFocus`; with none, to the item that had the focus before Tab came
  in, if it is still there. A menu opened from a button gives the focus back
  to that button when it closes, unless the user clicked into something else.
  In `Scroll` mode, a focused button is scrolled into view. With
  `focusOnClick: false`, a click on a button never takes the focus from the
  editor.
- **Menu and popover buttons in the strip.** See item 11. Menus open beside a
  vertical strip, on the side with more room (a `ContextMenu` placed with
  `popup(button, x, y)`), and popovers use item 1's `side`.
- Margin and clamping (`margin`, `x`, `y` not assigned) are unchanged.
- `reserve`, the room an editor keeps free at the capsule's edge, is not
  provided: the app reads `width + margin * 2`.

Fit: nothing existing changes. The default (horizontal, `Menu`, no dimming)
draws exactly as in 1.4.0.

Open question: the 80 px and 0.35 are Notepad's numbers. Keep them as the
defaults, as above?

#### 11. Menu and popover buttons: `AtlasAction.menu` and `AtlasAction.popover`

The strip is built from `actions`, so a menu or popover button is an action
that opens something. No new type is added.

| Name | Type | Default | Description |
|---|---|---|---|
| `menu` | `T.Menu` | `null` | A `ContextMenu` the action's button opens instead of triggering. |
| `popover` | `T.Popup` | `null` | An `AtlasPopover` the button opens instead. |

Behaviour:

- A button for such an action is a `ButtonMenu` for screen readers, shows a
  checked look while its menu or popover is open, and never emits
  `triggered()` for the click. If both are set, `menu` wins.
- In the overflow menu a `menu` becomes a submenu with the same title and
  symbol. A `popover` becomes an item that, when chosen, opens the popover
  from the "more" button.
- `AtlasFloatingToolbar` and `AtlasToolbar` treat the open state as "keep
  active". The popover's `target` is the button; the app need not set it.
- In `AtlasAppMenu` (item 12), an action with a `menu` shows as a submenu.
  `popover` is ignored there.
- `AtlasShortcuts` still registers the action; its shortcut, if any, runs
  `triggered()` as it always did.

Open question: `AtlasAction` grows two members that only toolbars use. The
alternative is a small set of entry types; I rejected it because every one
needs a collision check and a docs page, and the action already is the
toolbar's model. Decide.

### AtlasAppMenu

#### 12. Replace Notepad's GlobalMenu and FallbackMenu (Notepad)

No new members on the control except `exportShortcuts` and `modelActivated`.
The change is in what `menus` accepts.

| Name | Type | Default | Description |
|---|---|---|---|
| `exportShortcuts` | `bool` | `false` | Shows each entry's `shortcut` in the global menu. |
| `modelActivated(string id, var modelData, int index)` | signal | n/a | A model-driven row was chosen. |

`menus` stays `[{title, actions}]`. An entry of `actions` may now be:

| Entry | Meaning |
|---|---|
| an Action | as today |
| `null` | a separator, as today |
| `{ action, shortcut }` | an Action with the sequence to export (a string or a `StandardKey`) |
| `{ title, actions }` | a nested submenu, to eight levels; deeper is ignored with one warning |
| `{ id, title, model, textRole, lead, trail, emptyText }` | a submenu whose rows come from `model`, between the `lead` and `trail` action lists |

Behaviour:

- **Nested submenus.** Both the button's menus and the exported global menu
  nest to the same depth. The arrow keys follow `ContextMenu`: Right opens
  (Left in RTL), the opposite closes.
- **Model-driven rows.** A row's text is `modelData` for a string model, else
  `modelData[textRole]` (a `ListModel` is read through `textRole`). Choosing
  a row emits `modelActivated(id, modelData, index)`; the menu does nothing
  else. `lead` is a list of actions and `null`s before the rows (Reopen Closed
  Tab and a separator) and `trail` after them (a separator and Clear List).
  With no rows and `emptyText` set, one disabled row shows it. The submenu's
  entry is disabled when it has no rows and no enabled action in `lead` or
  `trail`. A change of the model while the menu is open takes effect when it
  closes, as AtlasToolbar's overflow does.
- **Shortcuts in the export.** Without `exportShortcuts` nothing changes. With
  it, native items hold the entry's `shortcut` (the global-menu protocol shows
  it) and the button's menu rows show it as text. The action must then leave
  its own `shortcut` empty, or the key has two owners and neither fires; this
  is documented, and AtlasShortcuts' duplicate warning covers a mistake.
- **Long groups.** A menu taller than the window already scrolls (ContextMenu
  caps at the window's height less its margins on `main`), so the request is
  met with no change. Notepad's workaround can go.
- Text of entries is plain. A `title` or `emptyText` is never HTML.

Open question: `exportShortcuts` leaves the double-ownership trap to the app.
The only way to remove it is to let AtlasAction release its own shortcut,
which needs Qt Quick internals. Recommendation: leave as designed.

### AtlasFormat

#### 13. SI bytes (Updater)

Two overloads, one new parameter each:

| Method | Description |
|---|---|
| `bytes(n: double, precision: int, locale: string, system: string): string` | `system` is `"iec"` (default, today) or `"si"`. |
| `bytesPerSecond(n: double, precision: int, locale: string, system: string): string` | The same, with "/s". |

`"si"` uses 1000 and the units `B`, `kB`, `MB`, `GB`, `TB`, `PB`: 1 200 000 000
is "1.2 GB". An unknown `system` is `"iec"`. Precision, locale and invalid
numbers behave as now ("" for NaN and infinity).

#### 14. Long and sentence-start dates (Updater)

New `date()` styles; the signature is unchanged:

| Style | Example (en) | Description |
|---|---|---|
| `"longAtTime"` | "Thursday, 1 January 2099 at 03:00" | The locale's long date, the weekday, and the short time. |
| `"atTimeSentence"` | "Today at 9:41", "Yesterday at 9:41" | `"atTime"` with the first letter upper-cased. |
| `"relativeSentence"` | "Just now", "Yesterday" | `"relative"` with the first letter upper-cased. |

The "at" joiner is a translated string in `atlas-ui.ts`, as `"atTime"`'s is.
Upper-casing uses the locale's rules (Turkish dotted I) and does nothing for
scripts without case. `now` is honoured as for the old styles. An unknown
style is still the default style.

Open question: three style names, or one `"sentence"` flag? A flag needs a new
parameter. Recommendation: three names.

### AtlasTimePicker

#### 15. Arrow step and a minimum (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `minuteArrowStep` | `int` | `0` | The step of the minutes' arrow keys and wheel. 0 follows `minuteStep`. |
| `minimumHours` | `int` | `0` | The earliest hour. |
| `minimumMinutes` | `int` | `0` | The earliest minute when the hour equals `minimumHours`. |
| `adjusted()` | signal | n/a | A typed or stepped time was changed to fit the minimum or the step. |

Behaviour:

- `minuteStep` keeps its meaning: the grid of allowed minutes. For Updater's
  case, leave it at 1 and set `minuteArrowStep: 5`: a typed 07 stays 07, and
  an arrow goes to the next or previous multiple of 5 (07 up is 10, down is
  05). The step is held to 1..30.
- With a minimum, a time before it is raised to it, `adjusted()` is emitted
  and a screen reader hears "Set to 09:00" (`Accessible.announce`). Hours and
  minutes do not wrap past the minimum: Down at the minimum stays. With no
  minimum the fields wrap as now.
- In 12-hour mode the minimum is in 24-hour terms; AM and PM are skipped if
  they would be before it.
- Clamping the app's own `hours` and `minutes` stays as documented (the
  exception in rule point 1).
- `adjusted()` is for apps that want to show a message. Typed text outside
  0 to 59 is ignored and the field restores its value, as today.

### ConfirmDialog

#### Dropped: `width` and `maximumWidth` (Updater)

`width` is an ordinary property: `width: Math.min(Kirigami.Units.gridUnit * 32,
parent.width - Kirigami.Units.gridUnit * 2)` replaces the 25 grid units
today. The body wraps to the new width. Nothing to add.

### AtlasCopyButton

#### 16. A text mode (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `label` | `string` | `""` | Text beside the icon ("Copy Details"). Empty keeps the icon-only button. |
| `copiedLabel` | `string` | `qsTr("Copied")` | The text shown for 1.5 s after a copy. |

`text` stays the string that is copied. With `label` set the button is
`TextBesideIcon`, its accessible name is `label`, and after a copy the text
and the check mark swap to `copiedLabel` (the width is that of the wider text,
so nothing jumps). The tooltip is dropped in text mode, since the label says
it. `copied()` and the announcement are unchanged; the announcement says
`copiedLabel`. Under reduced motion the swap is immediate.

### AtlasWindow

#### 17. Tunable width classes (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `compactBreakpoint` | `real` | `30` | Below this width, in grid units, `widthClass` is `Compact`. |
| `wideBreakpoint` | `real` | `60` | From this width, `widthClass` is `Wide`. |

Behaviour: named as `AtlasDetailGrid.columnsBreakpoint`, in grid units, so the
text size scales them. `widthClass` and `sidebarCollapsed` follow, so Updater
sets `compactBreakpoint: 38`. A value that is not a finite number above 0 uses
the default. If `compactBreakpoint` is not below `wideBreakpoint` there is no
`Medium`: below `compactBreakpoint` is `Compact`, otherwise `Wide`. Both are
read in bindings, so the class updates when either changes. `widthClass` stays
read-only.

### InfoBanner

#### 18. `shown` stays bound (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `dismissed` | `bool` (read-only) | `false` | The user closed the banner. It stays closed until reset. |

Behaviour:

- The close button sets an internal `_dismissed` flag and emits `closed()`. It
  no longer writes `shown`, so an app's `shown: x` keeps working.
- The banner is open when `shown && !_dismissed`. `dismissed` shows the flag.
- A new `text`, a new `type`, or `shown` going false resets the flag. So a
  later error, or the condition clearing and returning, shows it again.
- Slide, announcement, `closable`, `closeName` and `actions` are unchanged.

This is the one place a meaning changes: after a click on the cross, `shown`
reads true, where 1.4.0 read false. Updater and Monitor use `closable` banners. No app reads `shown` back
(searched), but Monitor writes it imperatively (see the question below).

Open question (important): Monitor sets `shown: false` and later writes
`notice.shown = true` when something reports. After a dismissal with the same
`text`, that write changes nothing (it is already true) and the banner stays
closed. Monitor's pages (AppsPage, EnergyPage, ServicesPage, SettingsPage) do this,
and SettingsPage's `missing.shown = !openUpdater()` has no new text to reset
the flag. They would break, so this needs the decision. The alternative is
rule point 2: hold `shown` false with a `Binding` while dismissed, restoring
the app's binding or its last value on reset. That keeps 1.4.0's `shown`
semantics and imperative re-show, at the cost of the lead's wording. Decide.

### AtlasAboutPage

#### 19. Rows, links (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `showSystemRows` | `bool` | `true` | False hides the "Operating system" and "Qt" rows. The Version and License rows stay. |
| `links` | `var` | `[]` | `[{title, url}]`. A non-empty list replaces the Source code and Report a problem rows. |

Behaviour:

- A row in `links` is a chevron `SectionRow` that opens `url`. Only `https`,
  `http` and `mailto` URLs are opened; any other scheme, or an empty one, is
  skipped with one warning (S gate: no `file:` or custom scheme from app data).
  An empty `links` keeps the built-in rows, which come from `AtlasApp`.
- `systemInfo()` and the "Copy system info" button still report the OS and Qt:
  a hidden row is not removed from a bug report.
- A row without a `title` is skipped.

Dropped as already possible: "a footer". Anything declared inside the page is
`extraContent`, added after the built-in sections, so it already is the last
thing on the page.

### AtlasDetailGrid

#### 20. A title and a footer (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `title` | `string` | `""` | A heading above the grid, styled like a `Section` title. |
| `footer` | `string` | `""` | A muted note below it, like `Section.footer`. |
| `framed` | `bool` | `false` | Draws the card a `Section` has round the grid. |

With `framed` the grid, title and footer look like a `Section` of label/value
rows and can replace one. The label column, `columns`, `columnsBreakpoint`,
`mono` and `copyable` are unchanged. The grid is a group for screen readers,
named `title`; `footer` is its description. Plain text only. Empty strings
take no room.

### AtlasBreadcrumb

#### 21. The "Hidden folders" text (study 3)

| Name | Type | Default | Description |
|---|---|---|---|
| `hiddenText` | `string` | `qsTr("Hidden folders")` | The title of the menu behind the "more" crumb, and its accessible name. |

Both places that use the string today read this property. A translation of
the default stays in `atlas-ui.ts`.

### AtlasCodeView (B1)

#### 22. An inset (Updater)

| Name | Type | Default | Description |
|---|---|---|---|
| `inset` | `bool` | `false` | Gives an unframed view the same leading and trailing room as `SectionRow` text. |

A framed view already pads by `AtlasStyle.spacingLarge`, which is what
`SectionRow` uses, so `inset` changes only the unframed one: it is the same
padding, kept apart from the card. In RTL it applies to both sides.

The scroll bar covering the last line is a bug, not API: the view moves to
`AtlasScrollBar` and reserves the bar's thickness on the side and at the
bottom while the bar shows, so the last line and the horizontal bar do not
overlap, also at the end of a scroll capped by `maximumHeight`. It is fixed in
B1 with its own test.

### TextButton (B1)

#### 23. No `variant`: fix the docs

Decision: TextButton does not get `variant`. The docs are wrong, not the
control: `docs/reference/atlas-ui/atlas-button.md` lists TextButton among the
buttons that are AtlasButton "with a preset look". It is a
`T.AbstractButton` with its own link look.

- Change `atlas-button.md` so TextButton is not called an AtlasButton preset.
  `text-button.md` already says it has no properties of its own.
- For a link-looking button with a variant, there is no change: TextButton is
  the link look. `AtlasButton { variant: AtlasButton.Ghost }` is not a link
  (its text is not the accent).

Open question: if Updater needs a Ghost button with accent text, that would be
a new value on `AtlasButton.Variant` (`Link`), which is additive and cheap.
Is that the real request? The roadmap says "Ghost link buttons".

## Items dropped as already possible

| Request | How it is met today |
|---|---|
| ConfirmDialog `width` / `maximumWidth` | Set `width`. |
| ToolbarButton multi-key shortcuts | `shortcutText` is free text. |
| AtlasAboutPage footer | Declare it inside the page. |
| AtlasAppMenu tall groups | ContextMenu already caps at the window's height less margins and scrolls. |
| AtlasHeaderBar `leading`/`trailing` capped at half | Already so in 1.4.0. |
| AtlasSidebar footer, second request (Updater) | Merged into item 6. |
| TextButton `variant` | Not added; docs corrected (item 23). |

## Summary of open questions

1. The binding rule's `Binding.RestoreBinding` behaviour, and the fallback.
2. InfoBanner: lead's `dismissed` wording against holding `shown` (item 18).
3. `AtlasAction.menu` and `popover` against new entry types (item 11).
4. `AtlasAppMenu` shortcut double ownership (item 12).
5. TextButton: docs only, or a `Link` variant on AtlasButton (item 23).
6. Dialog scroll-to-top on open (item 3).
7. Footer drop behaviour (item 6), `toolTipText` (item 8), floating toolbar
   defaults (item 10), date style names (item 14).
