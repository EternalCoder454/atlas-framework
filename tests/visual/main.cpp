// Visual tests for Atlas.Ui: every ui/gallery/demos/*Demo.qml is loaded, grabbed
// and compared with a golden image. See tests/README.md.
//
// Environment (set by run-variant.sh through ctest):
//   ATLAS_DEMO_DIR      the demos directory (required)
//   ATLAS_DEMO_FILTER   regular expression on the demo name (without "Demo")
//   ATLAS_GOLDEN_DIR    goldens, one directory per variant
//   ATLAS_OUT_DIR       where actual and diff images of a failure go
//   ATLAS_VARIANT       light, dark, accent or opaque
//   ATLAS_UPDATE_GOLDENS=1 rewrites the goldens instead of comparing
#include "../demolist.h"

#include <QtQuickTest/quicktest.h>

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>

namespace {

// A pixel differs when any channel is off by more than this ...
constexpr int kChannelTolerance = 2;
// ... and the picture fails when more than this share of its pixels differ.
constexpr double kMaxDifferingShare = 0.001;

QString env(const char *name, const QString &fallback = {})
{
    const QByteArray value = qgetenv(name);
    return value.isEmpty() ? fallback : QString::fromLocal8Bit(value);
}

// Writes `image` as a PNG through a temporary file, so a crash never leaves
// half a golden in the tree.
bool savePng(const QImage &image, const QString &path)
{
    if (!QDir().mkpath(QFileInfo(path).absolutePath())) {
        return false;
    }
    QSaveFile file(path);
    return file.open(QIODevice::WriteOnly) && image.save(&file, "PNG") && file.commit();
}

} // namespace

class Goldens : public DemoList
{
    Q_OBJECT
public:
    // True when this run rewrites the goldens instead of comparing.
    Q_INVOKABLE bool updating() const { return qEnvironmentVariableIntValue("ATLAS_UPDATE_GOLDENS") == 1; }
    Q_INVOKABLE QString variant() const { return env("ATLAS_VARIANT", QStringLiteral("light")); }

    // Grabs `target` (an Item, or a window) and compares it with the golden of
    // `name`. Returns "" when it matches, else a sentence for the failure.
    Q_INVOKABLE QString check(QObject *target, const QString &name) const
    {
        QImage actual = grab(target);
        if (actual.isNull()) {
            return QStringLiteral("%1: could not grab the picture (is the item visible?)").arg(name);
        }
        actual = actual.convertToFormat(QImage::Format_RGB32);

        const QString goldenPath = QDir(env("ATLAS_GOLDEN_DIR")).filePath(variant() + QLatin1Char('/') + name + QStringLiteral(".png"));
        const QString outBase = QDir(env("ATLAS_OUT_DIR", QStringLiteral("visual-out"))).filePath(variant() + QLatin1Char('/') + name);
        const QString actualPath = outBase + QStringLiteral(".actual.png");
        const QString diffPath = outBase + QStringLiteral(".diff.png");

        if (qEnvironmentVariableIntValue("ATLAS_UPDATE_GOLDENS") == 1) {
            if (!savePng(actual, goldenPath)) {
                return QStringLiteral("%1: could not write %2").arg(name, goldenPath);
            }
            return {};
        }

        QImage golden(goldenPath);
        if (golden.isNull()) {
            savePng(actual, actualPath);
            return QStringLiteral("%1: no golden at %2 (actual picture: %3). Run with ATLAS_UPDATE_GOLDENS=1 and commit the result.")
                .arg(name, goldenPath, actualPath);
        }
        golden = golden.convertToFormat(QImage::Format_RGB32);

        if (golden.size() != actual.size()) {
            savePng(actual, actualPath);
            return QStringLiteral("%1: size %2x%3, golden is %4x%5 (actual picture: %6)")
                .arg(name)
                .arg(actual.width())
                .arg(actual.height())
                .arg(golden.width())
                .arg(golden.height())
                .arg(actualPath);
        }

        QImage diff = actual;
        {
            QPainter painter(&diff);
            painter.fillRect(diff.rect(), QColor(255, 255, 255, 190));
        }
        qint64 differing = 0;
        for (int y = 0; y < actual.height(); ++y) {
            const QRgb *a = reinterpret_cast<const QRgb *>(actual.constScanLine(y));
            const QRgb *g = reinterpret_cast<const QRgb *>(golden.constScanLine(y));
            QRgb *d = reinterpret_cast<QRgb *>(diff.scanLine(y));
            for (int x = 0; x < actual.width(); ++x) {
                if (qAbs(qRed(a[x]) - qRed(g[x])) > kChannelTolerance || qAbs(qGreen(a[x]) - qGreen(g[x])) > kChannelTolerance
                    || qAbs(qBlue(a[x]) - qBlue(g[x])) > kChannelTolerance) {
                    ++differing;
                    d[x] = qRgb(255, 0, 0);
                }
            }
        }
        const qint64 total = qint64(actual.width()) * actual.height();
        if (double(differing) <= kMaxDifferingShare * double(total)) {
            QFile::remove(actualPath);
            QFile::remove(diffPath);
            return {};
        }
        savePng(actual, actualPath);
        savePng(diff, diffPath);
        return QStringLiteral("%1: %2 of %3 pixels differ (%4%, limit %5%). actual: %6  diff: %7  golden: %8")
            .arg(name)
            .arg(differing)
            .arg(total)
            .arg(100.0 * double(differing) / double(total), 0, 'f', 2)
            .arg(kMaxDifferingShare * 100.0, 0, 'f', 2)
            .arg(actualPath, diffPath, goldenPath);
    }

private:
    static QImage grab(QObject *target)
    {
        if (auto *window = qobject_cast<QQuickWindow *>(target)) {
            return window->grabWindow();
        }
        auto *item = qobject_cast<QQuickItem *>(target);
        if (!item || !item->window()) {
            return {};
        }
        // The whole window, so popups (which live in the overlay) are in the
        // picture, cropped to the demo's rectangle.
        const QImage image = item->window()->grabWindow();
        const QRect area = item->mapRectToScene(item->boundingRect()).toAlignedRect().intersected(image.rect());
        return area.isEmpty() ? QImage() : image.copy(area);
    }
};

class Setup : public QObject
{
    Q_OBJECT
public slots:
    void applicationAvailable()
    {
        // A fixed font, so the pictures do not depend on the machine's setting.
        QGuiApplication::setFont(QFont(QStringLiteral("Noto Sans"), 10));
    }
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->rootContext()->setContextProperty(QStringLiteral("Goldens"), &m_goldens);
    }

private:
    Goldens m_goldens;
};

QUICK_TEST_MAIN_WITH_SETUP(atlas_visual, Setup)

#include "main.moc"
