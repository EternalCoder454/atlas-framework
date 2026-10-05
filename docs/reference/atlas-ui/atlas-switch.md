---
title: AtlasSwitch
summary: A pill switch with an accent track when on and a knob that slides across with a small overshoot.
section: Buttons
since: "1.3.0"
---

A pill switch: an accent track when on, and a knob that slides across with a small overshoot (not under reduced motion). Off shows a visible edge, also when disabled. Use it for a setting that takes effect at once; for a choice that needs confirming, use a check box.

AtlasSwitch is a Qt Quick Controls [`Switch`](https://doc.qt.io/qt-6/qml-qtquick-templates-switch.html); `checked` and `toggled` work as usual. It draws only the track and the knob: `text` is not shown, it is only the accessible name. Put the visible label beside it, usually as the title of a [SectionRow](section-row.md).

## Example

```qml
SectionRow {
    title: qsTr("Show hidden files")

    AtlasSwitch {
        text: qsTr("Show hidden files") // the accessible name; the row shows the label
        checked: view.value("ShowHidden", false)
        onToggled: view.setValue("ShowHidden", checked)
    }
}
```

## Accessibility

Screen readers say "switch, on" rather than "check box, checked". The accessible name is `text`.

> [!NOTE]
> The label beside the switch is the app's: name the switch with `text` or `Accessible.name`.
