---
title: SectionRow
summary: One row in a Section: icon, title and subtitle, with a value, extra items, a check mark, a switch or a chevron.
section: Layout
---

SectionRow is a row of a [Section](section.md). It has an optional icon, a title and subtitle on the left, and a value, extra items, a check mark, a switch or a chevron on the right. A clickable row takes keyboard focus (Tab), shows a focus ring and activates with Enter or Space. A `radio` row also moves selection with Up and Down.

SectionRow is a `FocusScope`. It has three slots, all lists of items (since 1.4.0): `leading` (before the title; an avatar, a check box), `content` (replaces the title and subtitle column; a slider that spans the row) and `trailing` (the default property: a button, a combo box, a spin box).

## Example

```qml
Section {
    SectionRow {
        title: qsTr("Notifications")
        subtitle: qsTr("Show a banner when an update is ready")
        showSwitch: true
        switchChecked: settings.notify
        onSwitchToggled: checked => settings.notify = checked
    }
    SectionRow {
        title: qsTr("Language")
        value: qsTr("English")
        chevron: true
        onClicked: languagePage.open()
    }
}
```

## A permission row

An app's permission list needs no type of its own: a row with a leading symbol, a `subtitle` and a trailing [TelamonBadge](telamon-badge.md) of type `"warning"` or `"error"` (since 1.5.0).

```qml
Section {
    SectionRow {
        title: qsTr("Files")
        subtitle: qsTr("Can read and write your home folder")
        leading: [
            Symbol { icon: Symbols.Folder }
        ]
        TelamonBadge { text: qsTr("Broad access"); type: "warning" }
    }
    SectionRow {
        title: qsTr("System bus")
        subtitle: qsTr("Can talk to every system service")
        leading: [
            Symbol { icon: Symbols.Shield }
        ]
        TelamonBadge { text: qsTr("Full access"); type: "error" }
    }
}
```

The badge is not a Tab stop and a screen reader reads its text after the row's title and subtitle.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `animated` | `bool` | `true` | Turns the busy spinner; false draws a fixed arc (for screenshots). |
| `telamonRow` | `bool` (read-only) | — | Always true; marks the item as a row so the first one can skip its separator. |
| `busy` | `bool` | `false` | Shows a spinner in place of the value and chevron; the row stays enabled but does not activate. |
| `byMouse` | `bool` | `false` | True after a click, so the focus ring shows for keyboard focus only. |
| `checkmark` | `bool` | `false` | Shows an accent check mark; on a `radio` row it is the checked state. |
| `chevron` | `bool` | `false` | Shows a chevron at the trailing end and, unless `clickable` is set, makes the row clickable. |
| `clickable` | `bool` | `chevron` | Whether the row takes focus, shows hover and focus feedback and emits `clicked()`. |
| `content` | `list<Item>` (read-only) | — | Items that replace the title and subtitle column (a slider that spans the row); give them `Layout.fillWidth`. |
| `density` | `int` | `TelamonStyle.density` | `TelamonStyle.Normal` or `TelamonStyle.Compact`; Compact shrinks the height and vertical padding to about 75%. |
| `disclosure` | `bool` | `false` | Turns the chevron a quarter turn when `expanded` (for rows that open and close something). |
| `expanded` | `bool` | `false` | Whether a disclosure row is open. |
| `iconName` | `string` | `""` | A theme icon name shown before the title; ignored when `leading` has items. |
| `isFirst` | `bool` (read-only) | — | True for the first visible row in its `Section`, which draws no separator above itself. |
| `leading` | `list<Item>` (read-only) | — | Items before the title (an avatar, a check box); they replace the icon. Read-only list; add children by declaring them. |
| `mirrored` | `bool` (read-only) | — | True when the layout is mirrored (right-to-left). |
| `radio` | `bool` | `false` | Makes the row a radio button for screen readers; Up and Down move the selection to the neighbouring radio row. |
| `showSwitch` | `bool` | `false` | Shows a `TelamonSwitch` at the trailing end. |
| `subtitle` | `string` | `""` | A second, smaller line under the title. |
| `switchChecked` | `bool` | `false` | The state the switch shows. Bind it to the real setting: after `switchToggled` the switch goes back to this value. |
| `title` | `string` | `""` | The main text. |
| `trailing` | `list<Item>` (read-only) | — | The default property: items at the trailing end (a button, a combo box). They keep their own focus and Tab order after the row's. |
| `value` | `string` | `""` | Text at the trailing end, dimmed and elided; hidden while `busy`. |

## Signals

| Name | Description |
|---|---|
| `clicked()` | Emitted when the row is clicked or activated with Enter or Space. |
| `switchToggled(bool checked)` | Emitted when the user flips the switch; `checked` is the requested state. Write it to the setting, the switch shows `switchChecked`. |

## Methods

| Signature | Description |
|---|---|
| `activate(var event): var` | Handles Enter and Space: emits `clicked()` when the row itself has focus and is clickable. Called by the key handlers. |
| `ensureVisible(): var` | Scrolls the enclosing `Flickable` so the row is on screen. |
| `step(var forward, var event): var` | Moves focus and selection to the next (`forward`) or previous radio row; does nothing on a non-radio row. |

> [!NOTE]
> Items in `trailing` keep their own focus and Tab order after the row's, and a key they don't use doesn't activate the row. While `busy` the row stays enabled but does not activate.

## Accessibility

A clickable row is a button for screen readers, a `radio` row a radio button and any other a list item. Its description is the subtitle and value, and "Busy" while busy. A switch row is exposed through its switch only, so the name is not read twice.
