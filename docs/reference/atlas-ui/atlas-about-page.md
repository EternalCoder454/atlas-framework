---
title: AtlasAboutPage
summary: A ready-made About page: app icon, name, version, system info, links, licence and a "Copy system info" button.
section: Windows and pages
---

AtlasAboutPage is an [AtlasPage](atlas-page.md) every Atlas app can drop in. It shows the app's icon, name and version, an optional description, the OS and Qt in use, links to the source and the issue tracker, the licence, and a "Copy system info" button for bug reports. All of it comes from [AtlasApp](atlas-app.md), which reads the app's own name, version and desktop file name (set them on the application object at startup) and its `atlasRepo` property.

AtlasAboutPage inherits [AtlasPage](atlas-page.md), whose members are listed here too.

## Example

```qml
AtlasAboutPage {
    description: qsTr("Updates for AtlasOS.")
    license: qsTr("MIT")
    // Anything declared inside is added after the built-in sections.
    Section {
        title: qsTr("Credits")
        SectionRow { title: qsTr("Made by"); value: "Eterneon" }
    }
}
```

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `content` | `list<QtObject>` (default, read-only) | — | Items declared inside the page, placed in its column. For AtlasAboutPage, declared items go to `extraContent`. |
| `description` | `string` | `""` | One or two sentences under the version. Hidden when empty. |
| `extraContent` | `list<QtObject>` (default, read-only) | — | The default property: sections an app adds after the built-in ones. |
| `headerTrailing` | `list<QtObject>` (read-only) | — | Items at the trailing end of the title row (a button, a search field). The title elides before them. |
| `license` | `string` | `"MIT"` | The licence name shown in the About section. Hidden when empty. |
| `maxContentWidth` | `real` | 38 grid units | The widest the content grows. |
| `title` | `string` | `qsTr("About")` | The page's large bold title. |

## Methods

| Signature | Description |
|---|---|
| `ensureVisible(QVariant item): QVariant` | Scrolls just enough to show `item`. Does nothing for a click (mouse focus) or for an item outside the page's column. The page calls it itself when keyboard focus moves. |
| `systemInfo(): QString` | Plain text for a bug report: app name and version, ID, Atlas.Ui and Qt versions, OS and platform. The same text the "Copy system info" button copies. |
