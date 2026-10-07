#include "telamonclipboard.h"

#include <QClipboard>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QMimeData>
#include <QSet>
#include <QUrl>
#include <QtGlobal>

namespace {
constexpr int kAllocationLimitMb = 256; // Qt's own default
const QSet<QByteArray> kFormats = {"png", "jpeg", "jpg", "webp", "gif", "bmp"};

// Reads a local image file within the size caps; a null image otherwise.
QImage loadLocalImage(const QUrl &url)
{
    if (!url.isLocalFile()) {
        qWarning("TelamonClipboard.setImage: only local files are accepted");
        return {};
    }
    const QString path = url.toLocalFile();
    const QFileInfo info(path);
    if (!info.isFile() || !info.isReadable()) {
        qWarning("TelamonClipboard.setImage: not a readable file");
        return {};
    }
    if (info.size() > TelamonClipboard::MaxImageBytes) {
        qWarning("TelamonClipboard.setImage: file is larger than 64 MB");
        return {};
    }
    // A global limit of 0 means "no limit": never decode without one.
    if (QImageReader::allocationLimit() == 0) {
        QImageReader::setAllocationLimit(kAllocationLimitMb);
    }
    QImageReader reader(path);
    // Only the plain picture formats, by content: no svg (it can pull in other
    // files), no exotic plugins.
    const QByteArray format = reader.format().toLower();
    if (!kFormats.contains(format)) {
        qWarning("TelamonClipboard.setImage: this image format is not accepted (png, jpeg, webp, gif, bmp)");
        return {};
    }
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    // Refuse a small file that decodes to a huge picture; an unknown size is
    // checked after decoding by the same cap.
    if (size.isValid() && qint64(size.width()) * size.height() * 4 > TelamonClipboard::MaxImageBytes) {
        qWarning("TelamonClipboard.setImage: image is too large");
        return {};
    }
    QImage image = reader.read();
    if (image.isNull() || image.sizeInBytes() > TelamonClipboard::MaxImageBytes) {
        qWarning("TelamonClipboard.setImage: cannot read the image");
        return {};
    }
    return image;
}
}

TelamonClipboard::TelamonClipboard(QObject *parent)
    : QObject(parent)
{
    if (QClipboard *cb = board()) {
        connect(cb, &QClipboard::dataChanged, this, &TelamonClipboard::changed);
    }
}

QClipboard *TelamonClipboard::board() const
{
    return qGuiApp ? QGuiApplication::clipboard() : nullptr;
}

bool TelamonClipboard::hasText() const
{
    const QClipboard *cb = board();
    const QMimeData *data = cb ? cb->mimeData() : nullptr;
    return data && data->hasText();
}

bool TelamonClipboard::hasImage() const
{
    const QClipboard *cb = board();
    const QMimeData *data = cb ? cb->mimeData() : nullptr;
    return data && data->hasImage();
}

void TelamonClipboard::setText(const QString &text)
{
    if (QClipboard *cb = board()) {
        cb->setText(text);
    }
}

QString TelamonClipboard::text() const
{
    const QClipboard *cb = board();
    return cb ? cb->text() : QString();
}

void TelamonClipboard::setRichText(const QString &html, const QString &plainFallback)
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

bool TelamonClipboard::setImage(const QVariant &value)
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
