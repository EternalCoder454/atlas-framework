---
title: StepItem
summary: One step in a setup sidebar: a numbered circle, or a check mark once done, and the step's name.
section: Navigation
---

StepItem is one step of a setup or wizard sidebar. The current step gets the selection highlight. Only done steps can be clicked, to go back to them. Stack several in a column and set `number`, `current` and `done` from the wizard's state.

StepItem is a Qt Quick Templates `AbstractButton` ([Qt documentation](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html)); its inherited properties (`text`, `clicked`) work as usual.

## Example

```qml
Column {
    StepItem { number: 1; text: qsTr("Language"); done: true; onClicked: goTo(0) }
    StepItem { number: 2; text: qsTr("Disk"); current: true }
    StepItem { number: 3; text: qsTr("Summary") }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `clickable` | `bool` | `done && !current` | Whether the step can be clicked, to go back to it. Not `enabled`: a disabled item gets disabled colours and the current step must keep its accent. |
| `current` | `bool` | `false` | Marks the step the user is on: draws the selection highlight. |
| `done` | `bool` | `false` | Shows a check mark in place of the number. |
| `number` | `int` | `1` | The number in the circle. |

## Accessibility

Each step is a list item whose description is "Current step", "Done" or "Not done yet". Only a clickable step takes keyboard focus; Return and Enter click it.
