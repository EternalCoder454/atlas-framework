---
title: TelamonTransparencySwitch
summary: A settings row with a switch for the "Transparency and blur" setting every Telamon app shares.
section: Layout
since: "1.4.0"
---

TelamonTransparencySwitch is a [SectionRow](section-row.md) with a switch bound to `Appearance.transparency`, stored as `Transparency` under `[Appearance]` in telamonrc. Put it in a [Section](section.md) on the settings page. Turning it off makes every window, menu, dialog and tooltip solid. When the compositor offers no blur the switch is off and dimmed and the subtitle says why; the title and the subtitle keep the colours of any row (before 2.0.6 the whole row was dimmed, below 2:1 contrast, and the switch still showed on).

All properties, signals and methods are those of `SectionRow`; the row sets `title`, `subtitle`, `leading` (a blur symbol), `showSwitch`, `switchChecked` and `switchEnabled` itself.

## Example

```qml
Section {
    TelamonTransparencySwitch {}
}
```

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
| `switchEnabled` | `bool` | `true` | `false` dims the switch and takes its input, while the title and subtitle keep their colours (`enabled: false` dims the whole row). Since 2.0.6. |
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
> Don't set the properties the row binds (`title`, `subtitle`, `switchChecked`, `switchEnabled`): it follows `Appearance.blurAvailable` and `Appearance.effective`.
