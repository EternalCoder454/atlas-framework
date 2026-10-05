#include "atlasclipboard.h"

#include <QClipboard>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QMimeData>
#include <QUrl>
#include <QtGlobal>

namespace {
// Reads a local image file within the size caps; a null image otherwise.
QImage loadLocalImage(const QUrl &url)
{
    if (!url.isLocalFile()) {
        qWarning("AtlasClipboard.setImage: only local files are accepted");
        return {};
    }
    const QString path = url.toLocalFile();
    const QFileInfo info(path);
    if (!info.isFile() || !info.isReadable()) {
        qWarning("AtlasClipboard.setImage: not a readable file");
        return {};
    }
    if (info.size() > AtlasClipboard::MaxImageBytes) {
        qWarning("AtlasClipboard.setImage: file is larger than 64 MB");
        return {};
    }
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    // Refuse a small file that decodes to a huge picture; an unknown size is
    // checked after decoding by the same cap.
    if (size.isValid() && qint64(size.width()) * size.height() * 4 > AtlasClipboard::MaxImageBytes) {
        qWarning("AtlasClipboard.setImage: image is too large");
        return {};
    }
    QImage image = reader.read();
    if (image.isNull() || image.sizeInBytes() > AtlasClipboard::MaxImageBytes) {
        qWarning("AtlasClipboard.setImage: cannot read the image");
        return {};
    }
    return image;
}
}

AtlasClipboard::AtlasClipboard(QObject *parent)
    : QObject(parent)
{
    if (QClipboard *cb = board()) {
        connect(cb, &QClipboard::dataChanged, this, &AtlasClipboard::changed);
    }
}

QClipboard *AtlasClipboard::board() const
{
    return qGuiApp ? QGuiApplication::clipboard() : nullptr;
}

bool AtlasClipboard::hasText() const
{
    const QClipboard *cb = board();
    const QMimeData *data = cb ? cb->mimeData() : nullptr;
    return data && data->hasText();
}

bool AtlasClipboard::hasImage() const
{
    const QClipboard *cb = board();
    const QMimeData *data = cb ? cb->mimeData() : nullptr;
    return data && data->hasImage();
}

void AtlasClipboard::setText(const QString &text)
{
    if (QClipboard *cb = board()) {
        cb->setText(text);
    }
}

QString AtlasClipboard::text() const
{
    const QClipboard *cb = board();
    return cb ? cb->text() : QString();
}

void AtlasClipboard::setRichText(const QString &html, const QString &plainFallback)
{
    QClipboard *cb = board();
    if (!cb) {
        return;
    }
    auto *data = new QMimeData; // the clipboard takes it
    data->setHtml(html);
    data->setText(plainFallback);
    cb->setMimeData(data);
}

bool AtlasClipboard::setImage(const QVariant &value)
{
    QClipboard *cb = board();
    if (!cb) {
        return false;
    }
    QImage image;
    if (value.metaType() == QMetaType::fromType<QImage>()) {
        image = value.value<QImage>();
    } else if (value.metaType() == QMetaType::fromType<QUrl>()) {
        image = loadLocalImage(value.toUrl());
    } else if (value.metaType() == QMetaType::fromType<QString>()) {
        image = loadLocalImage(QUrl::fromUserInput(value.toString(), QString(), QUrl::AssumeLocalFile));
    } else if (const auto *object = value.value<QObject *>()) {
        // A QQuickItemGrabResult handed over whole.
        image = object->property("image").value<QImage>();
    }
    if (image.isNull() || image.sizeInBytes() > MaxImageBytes) {
        return false;
    }
    cb->setImage(image);
    return true;
}
