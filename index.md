---
title: Telamon Framework
summary: The shared base of every Telamon app, with the Telamon.Ui QML controls, the icon fonts, the Rust crates for startup, settings, logging and system work, and the app template.
---

Telamon Framework is what every Telamon app is built on, so they all look and behave the same. Telamon OS installs it once and every app uses that copy. It runs on Qt 6.11 and KDE Frameworks 6 on Fedora 44.

## Which library to use

| You want to | Use |
|---|---|
| Build the app's interface: windows, pages, buttons, fields, lists, tables, dialogs, charts | [Telamon.Ui](telamon-ui/index.md), the QML module (`import Telamon.Ui`) |
| Show an icon | [Symbols](symbols/index.md): `Symbol { icon: Symbols.Home }` draws Material Symbols |
| Name the app, read its settings file, log to the journal | [telamon-framework-core](telamon-framework-core/index.md) |
| Start a GUI app: app ID, one instance per session, crash hooks, the Telamon.Ui version check | [telamon-framework-ui](telamon-framework-ui/index.md) |
| System work: crash reports, update history, bootc state, polkit checks, desktop notifications | [telamon-framework-system](telamon-framework-system/index.md) |
| Flatpak updates | [telamon-framework-flatpak](telamon-framework-flatpak/index.md) |
| Start a new app | [The app template](template/index.md) |

A small app needs only Telamon.Ui and telamon-framework-ui, which brings in telamon-framework-core. Add the other crates only when the app does that kind of work.

## Getting started

1. Copy the [app template](template/index.md) and rename it. It builds on its own: a Rust backend through CXX-Qt, a QML interface on Telamon.Ui, and one line of C++ that starts the app.
2. Build on Fedora 44 with the `telamon-ui` package installed. Telamon.Ui is a QML module next to Qt's own, so the app writes `import Telamon.Ui` and links nothing.
3. Build pages from [TelamonWindow](telamon-ui/telamon-window.md), [TelamonPage](telamon-ui/telamon-page.md) and the controls. Colours, spacing, fonts and motion come from [TelamonStyle](telamon-ui/telamon-style.md), never hard-coded.
4. Run the framework's checks on the app (`tools/lint-app.sh` and `tools/check-app-names.sh` from the framework repository) in its CI.

```qml
import QtQuick
import Telamon.Ui

TelamonWindow {
    title: qsTr("Hello")
    width: 640
    height: 480
    visible: true

    TelamonPage {
        anchors.fill: parent
        title: qsTr("Hello")

        PrimaryButton {
            text: qsTr("Say hello")
            symbol: Symbols.WavingHand
            onClicked: console.log("hello")
        }
    }
}
```

## Versions

Telamon.Ui only ever adds API: a type, property, signal, function, enum value or symbol name is never renamed or removed in a later version. Each page says which version added it (`since`). An app declares the oldest Telamon.Ui it works with (`ui:` in `app!`), and at startup it refuses to run on an older one, with a plain message instead of a broken window.
