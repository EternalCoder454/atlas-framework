// State-contract test for Telamon.Ui: every ui/gallery/demos/*Demo.qml is loaded
// and checked against the "States" rules of docs/DESIGN.md. See
// tests/README.md and tst_state.qml. This file holds the helpers QML lacks:
// grabbing a rectangle of the window and comparing two pictures.
//
// Environment (set by visual/run-variant.sh through ctest): TELAMON_DEMO_DIR,
// TELAMON_DEMO_FILTER (see demolist.h), and TELAMON_STATE_SHARD="i/n" to run only
// every n-th demo starting at i (ctest runs the shards in parallel).
#include "../demolist.h"

#include <QtQuickTest/quicktest.h>

#include <QDir>
#include <QGuiApplication>
#include <cstdio>
#include <QImage>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>

namespace {

// The same tolerances as the visual test: a pixel differs when a channel is
// off by more than 2, and the pictures differ when more than 0.1% of the
// pixels do (so at least one pixel of a small area).
constexpr int kChannelTolerance = 2;
constexpr double kMaxDifferingShare = 0.001;

} // namespace

class States : public DemoList
{
    Q_OBJECT
public:
    // The demos of this shard (TELAMON_STATE_SHARD="i/n"), or all of them.
    Q_INVOKABLE QStringList shardDemos() const
    {
        const QStringList all = demos();
        const QStringList parts = qEnvironmentVariable("TELAMON_STATE_SHARD").split(QLatin1Char('/'));
        bool okIndex = false;
        bool okCount = false;
        const int index = parts.value(0).toInt(&okIndex);
        const int count = parts.value(1).toInt(&okCount);
        if (parts.size() != 2 || !okIndex || !okCount || count < 1 || index < 0 || index >= count) {
            return all;
        }
        QStringList mine;
        for (qsizetype i = 0; i < all.size(); ++i) {
            if (i % count == index) {
                mine << all.at(i);
            }
        }
        return mine;
    }

    // The window's picture, cropped to `target` (an Item) grown by `margin`
    // pixels on every side. A null image when the area is not on screen.
    Q_INVOKABLE QImage grab(QObject *target, int margin) const
    {
        auto *item = qobject_cast<QQuickItem *>(target);
        if (!item || !item->window()) {
            return {};
        }
        const QImage image = item->window()->grabWindow();
        const QRectF scene = item->mapRectToScene(item->boundingRect()).adjusted(-margin, -margin, margin, margin);
        const QRect area = scene.toAlignedRect().intersected(image.rect());
        return area.isEmpty() ? QImage() : image.copy(area).convertToFormat(QImage::Format_RGB32);
    }

    // True when the two pictures differ by more than the tolerance (or have
    // different sizes, or one is null).
    Q_INVOKABLE bool differs(const QImage &a, const QImage &b) const
    {
        if (a.isNull() || b.isNull() || a.size() != b.size()) {
            return true;
        }
        qint64 differing = 0;
        for (int y = 0; y < a.height(); ++y) {
            const QRgb *pa = reinterpret_cast<const QRgb *>(a.constScanLine(y));
            const QRgb *pb = reinterpret_cast<const QRgb *>(b.constScanLine(y));
            for (int x = 0; x < a.width(); ++x) {
                if (qAbs(qRed(pa[x]) - qRed(pb[x])) > kChannelTolerance || qAbs(qGreen(pa[x]) - qGreen(pb[x])) > kChannelTolerance
                    || qAbs(qBlue(pa[x]) - qBlue(pb[x])) > kChannelTolerance) {
                    ++differing;
                }
            }
        }
        return double(differing) > kMaxDifferingShare * double(qint64(a.width()) * a.height());
    }

    // One line on stderr (console.log is filtered by the test runner).
    Q_INVOKABLE void log(const QString &line) const { fprintf(stderr, "%s\n", qPrintable(line)); }

    // Writes a picture to TELAMON_OUT_DIR/<name>.png for a failure report.
    // Returns the path, or "" when it could not be written.
    Q_INVOKABLE QString save(const QImage &image, const QString &name) const
    {
        const QString base = qEnvironmentVariable("TELAMON_OUT_DIR", QStringLiteral("state-out"));
        QString safe = name;
        safe.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_.-]")), QStringLiteral("_"));
        const QString path = QDir(base).filePath(safe + QStringLiteral(".png"));
        if (image.isNull() || !QDir().mkpath(base)) {
            return {};
        }
        QSaveFile file(path);
        return file.open(QIODevice::WriteOnly) && image.save(&file, "PNG") && file.commit() ? path : QString();
    }

    Q_INVOKABLE bool isNull(const QImage &a) const { return a.isNull(); }

    // True when `item` is `ancestor` or inside it (through parentItem).
    Q_INVOKABLE bool isInside(QObject *item, QObject *ancestor) const
    {
        for (auto *i = qobject_cast<QQuickItem *>(item); i; i = i->parentItem()) {
            if (i == ancestor) {
                return true;
            }
        }
        return false;
    }

    // A readable name for an item: its type, object name and text.
    Q_INVOKABLE QString describe(QObject *item) const
    {
        if (!item) {
            return QStringLiteral("(none)");
        }
        QString name = QString::fromLatin1(item->metaObject()->className());
        const qsizetype at = name.indexOf(QLatin1String("_QMLTYPE_"));
        if (at > 0) {
            name.truncate(at);
        }
        if (name.startsWith(QLatin1String("QQuick"))) {
            name.remove(0, 6);
        }
        if (!item->objectName().isEmpty()) {
            name += QLatin1Char('#') + item->objectName();
        }
        const QVariant text = item->property("text");
        if (text.typeId() == QMetaType::QString && !text.toString().isEmpty()) {
            name += QStringLiteral(" \"%1\"").arg(text.toString().left(30));
        }
        return name;
    }
};

class Setup : public QObject
{
    Q_OBJECT
public slots:
    void applicationAvailable() { QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans"), 10)); }
    void qmlEngineAvailable(QQmlEngine *engine) { engine->rootContext()->setContextProperty(QStringLiteral("States"), &m_states); }

private:
    States m_states;
};

QUICK_TEST_MAIN_WITH_SETUP(telamon_state, Setup)

#include "main.moc"
