---
title: TelamonAvatar
summary: A round picture of a person or account, falling back to initials on a name-based colour, or a symbol.
section: Feedback and status
since: "1.4.0"
---

TelamonAvatar shows the image at `source`. With no image, or when it fails to load, it shows the initials of `name` ("Ada Lovelace" gives "AL") on a colour taken from the name, so the same person always has the same colour. With no name either, it shows `symbol` (a person by default). The colours are a fixed set that white text reads on (WCAG AA).

## Example

```qml
TelamonAvatar { name: user.displayName; source: user.picture; size: 48 }
```

> [!NOTE]
> The picture is cropped to a circle with a mask, which needs a GPU backend. On Qt Quick's software backend it stays square.

## Accessibility

A screen reader gets `accessibleName`: the `name`, or "Profile picture" when there is none.

## Properties

| Name | Type | Default | Description |
|---|---|---|---|
| `accessibleName` | `string` | `name`, or "Profile picture" | What a screen reader says. Set it for an avatar that has no name. |
| `name` | `string` | `""` | The person's name; gives the initials and the colour. |
| `size` | `real` | 2 grid units | The width and height in pixels. |
| `source` | `url` | empty | The image. The image is decoded at twice the drawn size, so it stays sharp on high-DPI screens. |
| `symbol` | `int` (a `Symbols.<Name>` value, see [Symbols](symbols.md)) | `Symbols.Person` | Shown when there is no image and no name. |
