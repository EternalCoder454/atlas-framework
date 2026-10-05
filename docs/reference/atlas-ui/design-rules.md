---
title: Design rules
summary: The rules every Atlas app follows, and which Atlas.Ui control or token carries each one.
section: Guides
order: 10
---

Every Atlas app follows these rules. Atlas.Ui implements them, so an app that builds its pages from Atlas.Ui's controls gets them for free. The framework's `tools/lint-app.sh` fails an app on the default buttons and warns on the other default controls.

## 1. macOS-style controls

- Small rounded-rectangle buttons (4 px corners): [PrimaryButton](primary-button.md) (filled with the accent), [SecondaryButton](secondary-button.md) (soft and tinted) and [TextButton](text-button.md) (a link).
- Round switches: [AtlasSwitch](atlas-switch.md).
- Settings grouped in rounded cards: [Section](section.md) of [SectionRow](section-row.md)s.
- A sidebar with a rounded-rectangle selection: [SidebarItem](sidebar-item.md) and [SidebarGroup](sidebar-group.md).
- A large bold page title: [AtlasPage](atlas-page.md).
- A big centred status: [StatusHero](status-hero.md).

## 2. Window caption buttons come from the window

AtlasOS's window decoration draws minimise, maximise and close as rounded squares: tinted at rest, accent on hover, red for close. An app never draws its own caption buttons. An app that wants one merged header row puts an [AtlasHeaderBar](atlas-header-bar.md) in its [AtlasWindow](atlas-window.md)'s `header`; the window then draws the caption buttons itself ([AtlasWindowButtons](atlas-window-buttons.md)) in the same look and in the desktop's button order.

## 3. One blur switch for every app

The window is [AtlasWindow](atlas-window.md). With "Transparency effects" on and a compositor that blurs, its background is the theme's background, partly see-through over the blurred desktop. With it off, the window is opaque. The switch is `Transparency` under `[Appearance]` in `~/.config/atlasrc` (default on), read and written through the [Appearance](appearance.md) singleton. A change in one app, or in the file, reaches every open Atlas app at once. [AtlasTransparencySwitch](atlas-transparency-switch.md) is a ready-made settings row for it. See [Style and theming](style-and-theming.md).

## 4. The logo plus a check mark when up to date

A screen that reports "all is well" (no updates, nothing to fix) shows the OS logo in its own colours with a check badge on its corner, not a tinted circle. Use [StatusHero](status-hero.md) with `iconName` set to the logo (`LOGO=` from os-release, then `distributor-logo`), `iconIsMask: false`, `showTintCircle: false` and `cornerBadgeIcon: "checkmark"`. Atlas Updater's Updates page is the model.

## 5. The Atlas look, on the Plasma theme

Calm and precise, Light and Dark equally.

- Violet is the accent (`AtlasStyle.accent`) for buttons and selection; pink-violet (`AtlasStyle.focus`) is for focus rings. When the user has chosen an accent in Plasma, that accent wins, as in other KDE apps.
- Fonts are IBM Plex Sans and JetBrains Mono for code (`AtlasStyle.fontFamily` and `monoFamily`), falling back to the system fonts. The application font's size stays the user's.
- Corners are small (4, 6 and 8) and motion is quick and subtle (100, 150 and 250 ms).
- Every colour comes from [AtlasStyle](atlas-style.md) or `Kirigami.Theme`, every size from `Kirigami.Units` or AtlasStyle's scale. No hard-coded colours, so light, dark and the user's accent all work.
- The Qt Quick Controls style is `org.kde.desktop`.

## 6. Never the default buttons

No `QQC2.Button`, `QQC2.ToolButton`, `QQC2.Switch` or buttons made from `Kirigami.Action` in an app's own pages: use Atlas.Ui's buttons and switch. The same goes for the controls Atlas.Ui now has: text fields, combo boxes, check boxes, sliders, spin boxes, tooltips and busy indicators. If Atlas.Ui lacks a control, it is added to Atlas.Ui rather than worked around with the default one.

## 7. Everyone can use it

- Every control has an accessible role and name, so screen readers can read it.
- Every control that acts takes keyboard focus and shows [AtlasFocusRing](atlas-focus-ring.md) when the focus came from the keyboard.
- Nothing animates while hidden, and nothing animates when Plasma's animation speed is "Instant" (the `AtlasStyle` durations are 0 then). See [Motion](motion.md).
- Text a user reads is in `qsTr()`.

See [Accessibility](accessibility.md) for the details.

## Icons

Icons are Material Symbols through [Symbol](symbol.md) and the `symbol:` property of buttons, sidebar items and menu items, or theme icons by name where a control takes `iconName`. See [Symbols](../symbols/index.md).

Only the selected item of a navigation control (a sidebar entry, tab bar or view switcher tab) turns solid with `Symbol.filled`. Everything else, selected or not, uses the outline. The selection tint of those controls is one rectangle that slides to the new item.

## States

Every control behaves the same way in each state, and the framework's tests check the ones that can be measured.

| State | What it does |
|---|---|
| Disabled (`enabled: false`) | Dimmed, takes no focus (Tab skips it), no hover or press reaction, no cursor change, reported as disabled to screen readers. A disabled parent disables its children. |
| Read only | The value is shown normally (not dimmed) and cannot be edited. The control keeps focus, selection and copy. |
| Error | The error colour (`AtlasStyle.error`) on the border or text, and a message beside the field. The message is announced to screen readers, not only coloured. |
| Busy | A spinner replaces the value or chevron. The control stays enabled but does not act again until the work ends, and says it is busy to screen readers. |
| Hover | A grey tint of the text colour (never the accent), only for a control that acts, never for a disabled or busy one. A clickable row or button shows a hand cursor. |
| Pressed | A stronger tint than hover, gone on release or when the pointer leaves. |
| Focus | [AtlasFocusRing](atlas-focus-ring.md), only for keyboard focus, never after a click. |

A control that holds other controls (a `SectionRow` with `trailing` items) shows its own ring only while it has focus itself, not while an item inside it does.
