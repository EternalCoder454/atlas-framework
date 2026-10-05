---
title: AtlasApp
summary: A read-only singleton with the running app's name, ID, version and repository, the OS, and the Qt and Atlas.Ui versions.
section: Services
---

AtlasApp is what an About page needs to know. The startup code of atlas-framework-ui sets the app's name, version and desktop file name on the application object. [AtlasAboutPage](atlas-about-page.md) shows it all. The OS values come from `os-release`, read once from `/etc/os-release`, else `/usr/lib/os-release`; nothing in the environment changes which file.

## Example

```qml
import QtQuick.Controls
import Atlas.Ui

Label {
    text: AtlasApp.name + " " + AtlasApp.version + " on " + AtlasApp.osPrettyName
}
```

> [!NOTE]
> The app's startup code names its repository by setting the `atlasRepo` property on the application object, for example `app.setProperty("atlasRepo", "atlasos-updater")`. Without it, `repo`, `sourceUrl` and `issuesUrl` are empty. A name with anything but letters, digits, `.`, `_` or `-` counts as no name.

All properties are constant. `uiVersion` is the version of Atlas.Ui itself, from the project version at build time. Apps name the oldest they work with and the startup checks it. Atlas.Ui before 1.3.0 has no `uiVersion`, which is how a startup check tells it is too old.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `id` | `string` (read-only) | — | The app's ID (its desktop file name). Also the icon name [AtlasAboutPage](atlas-about-page.md) shows. |
| `issuesUrl` | `string` (read-only) | — | The issue tracker of the repository; empty without `atlasRepo`. |
| `name` | `string` (read-only) | — | The application's name. |
| `osHomeUrl` | `string` (read-only) | — | The OS's home page (`HOME_URL` in os-release). |
| `osLogo` | `string` (read-only) | — | The OS's logo icon name (`LOGO` in os-release). |
| `osName` | `string` (read-only) | — | The OS's name (`NAME` in os-release). |
| `osPrettyName` | `string` (read-only) | — | The OS's display name (`PRETTY_NAME` in os-release). |
| `osVersion` | `string` (read-only) | — | The OS's version (`VERSION`, else `VERSION_ID`, in os-release). |
| `qtVersion` | `string` (read-only) | — | The Qt version in use. |
| `repo` | `string` (read-only) | — | The repository name under github.com/EternalCoder454/, from `atlasRepo`. |
| `sourceUrl` | `string` (read-only) | — | The repository's URL; empty without `atlasRepo`. |
| `uiVersion` | `string` (read-only) | — | The version of Atlas.Ui itself, such as `"1.4.0"`. |
| `version` | `string` (read-only) | — | The application's version. |
