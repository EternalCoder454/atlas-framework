// AtlasClipboard: the system clipboard for QML, in one place so no control
// needs a hidden TextEdit to copy. The app asks for everything: nothing is
// read until `text()` is called, and no content is ever logged.
//
//   AtlasClipboard.setText("hello")
//   AtlasClipboard.setRichText("<b>hello</b>", "hello")   // html + plain text
//   AtlasClipboard.setImage(grabResult.image)             // a QImage ...
//   AtlasClipboard.setImage("file:///home/me/shot.png")   // ... or a local file
//   if (AtlasClipboard.hasText) { field.text = AtlasClipboard.text() }
//
// Images from a file must be a local file of at most 64 MB (and at most 64 MB
// of pixels once decoded); anything else is refused and setImage() returns
// false. `hasText` and `hasImage` look at the formats on offer, not at the
// content, and changed() fires when the clipboard changes (in any app).
#pragma once

#include <QObject>
#include <QString>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class QClipboard;

class AtlasClipboard : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AtlasClipboard)
    QML_SINGLETON

    Q_PROPERTY(bool hasText READ hasText NOTIFY changed FINAL)
    Q_PROPERTY(bool hasImage READ hasImage NOTIFY changed FINAL)

public:
    explicit AtlasClipboard(QObject *parent = nullptr);

    // The largest image taken, in bytes (file size, and decoded size).
    static constexpr qint64 MaxImageBytes = 64 * 1024 * 1024;

    bool hasText() const;
    bool hasImage() const;

    // Puts plain text on the clipboard.
    Q_INVOKABLE void setText(const QString &text);
    // The clipboard's text, or an empty string.
    Q_INVOKABLE QString text() const;
    // Puts `html` (text/html) and `plainFallback` (text/plain) on the clipboard.
    Q_INVOKABLE void setRichText(const QString &html, const QString &plainFallback);
    // Puts an image on the clipboard: a QImage (a grab result's `image`), or
    // the url or path of a local image file. False when refused or unreadable.
    Q_INVOKABLE bool setImage(const QVariant &image);

Q_SIGNALS:
    void changed();

private:
    QClipboard *board() const;
};
