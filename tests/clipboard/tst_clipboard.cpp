// TelamonClipboard: text, rich text and image round trips through the in-process
// clipboard of the offscreen platform, and the refusals of setImage().
// Compiled straight from ui/telamonclipboard.cpp.
#include "telamonclipboard.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QUrl>
#include <QtTest>

class TestClipboard : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void text()
    {
        TelamonClipboard board;
        QSignalSpy spy(&board, &TelamonClipboard::changed);
        board.setText(QStringLiteral("hello é world"));
        QCOMPARE(board.text(), QStringLiteral("hello é world"));
        QVERIFY(board.hasText());
        QVERIFY(!board.hasImage());
        QVERIFY(spy.count() >= 1);
        const QMimeData *data = QGuiApplication::clipboard()->mimeData();
        QVERIFY(data->hasFormat(QStringLiteral("text/plain")));
        QVERIFY(!data->hasFormat(QStringLiteral("text/html")));
    }

    void emptyText()
    {
        TelamonClipboard board;
        board.setText(QString());
        QCOMPARE(board.text(), QString());
    }

    void richText()
    {
        TelamonClipboard board;
        board.setRichText(QStringLiteral("<b>bold</b>"), QStringLiteral("bold"));
        const QMimeData *data = QGuiApplication::clipboard()->mimeData();
        QVERIFY(data->hasFormat(QStringLiteral("text/html")));
        QVERIFY(data->hasFormat(QStringLiteral("text/plain")));
        QVERIFY(data->html().contains(QStringLiteral("<b>bold</b>")));
        QCOMPARE(board.text(), QStringLiteral("bold"));
    }

    void imageFromQImage()
    {
        TelamonClipboard board;
        QImage image(4, 3, QImage::Format_ARGB32);
        image.fill(Qt::red);
        QVERIFY(board.setImage(QVariant::fromValue(image)));
        QVERIFY(board.hasImage());
        QCOMPARE(QGuiApplication::clipboard()->image().size(), QSize(4, 3));
        QVERIFY(!board.setImage(QVariant::fromValue(QImage()))); // null
    }

    void imageFromFile()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(5, 2, QImage::Format_ARGB32);
        image.fill(Qt::blue);
        const QString path = dir.filePath(QStringLiteral("shot.png"));
        QVERIFY(image.save(path));

        TelamonClipboard board;
        QVERIFY(board.setImage(QUrl::fromLocalFile(path)));
        QCOMPARE(QGuiApplication::clipboard()->image().size(), QSize(5, 2));
        QVERIFY(board.setImage(path)); // a plain path
        QVERIFY(board.setImage(QUrl::fromLocalFile(path).toString()));
    }

    void imageRefused()
    {
        TelamonClipboard board;
        QVERIFY(!board.setImage(QUrl(QStringLiteral("https://example.org/a.png"))));
        QVERIFY(!board.setImage(QUrl(QStringLiteral("file://remote.example/etc/passwd")))); // not local
        QVERIFY(!board.setImage(QStringLiteral("/nonexistent/none.png")));
        QVERIFY(!board.setImage(QStringLiteral("/etc"))); // a directory
        QVERIFY(!board.setImage(QVariant()));
        QVERIFY(!board.setImage(42));

        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile junk(dir.filePath(QStringLiteral("junk.png")));
        QVERIFY(junk.open(QIODevice::WriteOnly));
        junk.write("not a png");
        junk.close();
        QVERIFY(!board.setImage(QUrl::fromLocalFile(junk.fileName())));

        // svg is not on the list of formats, whatever its name says.
        QFile svg(dir.filePath(QStringLiteral("pic.png")));
        QVERIFY(svg.open(QIODevice::WriteOnly));
        svg.write("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4\" height=\"4\"><rect width=\"4\" height=\"4\"/></svg>");
        svg.close();
        QVERIFY(!board.setImage(QUrl::fromLocalFile(svg.fileName())));
    }

    void imageFormatsAllowed()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QImage image(3, 3, QImage::Format_ARGB32);
        image.fill(Qt::red);
        TelamonClipboard board;
        for (const char *format : {"png", "jpg", "bmp", "gif"}) {
            const QString path = dir.filePath(QStringLiteral("p.") + QLatin1String(format));
            if (!image.save(path)) {
                continue; // plugin not built in
            }
            QVERIFY2(board.setImage(path), format);
        }
    }
};

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    TestClipboard test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_clipboard.moc"
