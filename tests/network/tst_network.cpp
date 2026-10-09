// What the QML engines of Telamon.Ui fetch (ui/telamonnetwork.cpp, compiled in):
// a cleartext address of another computer is refused at once, on every path
// that fetches (the access manager, an Image, a Kirigami.Icon), without a
// request leaving or the item asking again and again; an address on this
// computer and https are not touched.
#include "telamonnetwork.h"

#include <QtTest>

#include <QGuiApplication>
#include <QNetworkReply>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTcpServer>

class TestNetwork : public QObject
{
    Q_OBJECT
private Q_SLOTS:
    void allowed_data()
    {
        QTest::addColumn<QString>("url");
        QTest::addColumn<bool>("ok");
        QTest::newRow("https") << "https://example.org/a.png" << true;
        QTest::newRow("HTTPS upper") << "HTTPS://EXAMPLE.org/a.png" << true;
        QTest::newRow("file") << "file:///usr/share/a.png" << true;
        QTest::newRow("qrc") << "qrc:/a.png" << true;
        QTest::newRow("data") << "data:image/png;base64,AAAA" << true;
        QTest::newRow("http") << "http://example.org/a.png" << false;
        QTest::newRow("HTTP upper") << "HTTP://example.org/a.png" << false;
        QTest::newRow("ftp") << "ftp://example.org/a.png" << false;
        QTest::newRow("http ip") << "http://93.184.216.34/a.png" << false;
        QTest::newRow("http private") << "http://192.168.1.1/a.png" << false;
        QTest::newRow("http loopback name") << "http://localhost:8080/a.png" << true;
        QTest::newRow("http loopback name dot") << "http://localhost./a.png" << true;
        QTest::newRow("http loopback v4") << "http://127.0.0.1/a.png" << true;
        QTest::newRow("http loopback v4 other") << "http://127.1.2.3:9/a.png" << true;
        QTest::newRow("http loopback v6") << "http://[::1]/a.png" << true;
        QTest::newRow("http name starting like loopback") << "http://127.0.0.1.example.org/a.png" << false;
        QTest::newRow("http localhost suffix") << "http://localhost.example.org/a.png" << false;
        QTest::newRow("http userinfo trick") << "http://127.0.0.1@example.org/a.png" << false;
        QTest::newRow("http no host") << "http:///a.png" << false;
        QTest::newRow("empty") << "" << true;
    }
    void allowed()
    {
        QFETCH(QString, url);
        QFETCH(bool, ok);
        QCOMPARE(TelamonNetwork::allowed(QUrl(url)), ok);
    }

    // The access manager answers a refused request with an error (after a
    // moment) and sends nothing.
    void refusedRequestFails()
    {
        TelamonNetwork::AccessManager nam;
        const int before = TelamonNetwork::refusedCount();
        QNetworkReply *reply = nam.get(QNetworkRequest(QUrl(QStringLiteral("http://example.invalid/a.png"))));
        QSignalSpy finished(reply, &QNetworkReply::finished);
        QVERIFY(finished.wait(4000));
        QCOMPARE(reply->error(), QNetworkReply::ContentAccessDenied);
        QVERIFY(reply->isFinished());
        QCOMPARE(reply->readAll(), QByteArray());
        QCOMPARE(TelamonNetwork::refusedCount(), before + 1);
        delete reply;
    }

    // A request to this computer goes out as before.
    void loopbackRequestIsSent()
    {
        QTcpServer server;
        QVERIFY(server.listen(QHostAddress::LocalHost));
        TelamonNetwork::AccessManager nam;
        QNetworkReply *reply = nam.get(QNetworkRequest(QUrl(QStringLiteral("http://127.0.0.1:%1/a.png").arg(server.serverPort()))));
        QSignalSpy connection(&server, &QTcpServer::newConnection);
        QVERIFY(connection.wait(3000));
        delete reply;
    }

    // An Image and a Kirigami.Icon given a cleartext address: refused, they
    // end in an error, and they do not keep asking.
    void itemsDoNotFetchCleartext_data()
    {
        QTest::addColumn<QByteArray>("qml");
        QTest::newRow("Image") << QByteArray("import QtQuick\nImage { width: 32; height: 32; source: \"http://example.invalid/a.png\" }\n");
        QTest::newRow("AnimatedImage") << QByteArray("import QtQuick\nAnimatedImage { width: 32; height: 32; source: \"http://example.invalid/a.gif\" }\n");
        QTest::newRow("Kirigami.Icon") << QByteArray("import QtQuick\nimport org.kde.kirigami as Kirigami\nKirigami.Icon { width: 32; height: 32; source: \"http://example.invalid/a.png\" }\n");
    }
    void itemsDoNotFetchCleartext()
    {
        QFETCH(QByteArray, qml);
        QQuickView view;
        TelamonNetwork::install(view.engine());
        QVERIFY(view.engine()->networkAccessManagerFactory());
        QQmlComponent component(view.engine());
        component.setData(qml, QUrl());
        QVERIFY2(component.isReady(), qPrintable(component.errorString()));
        std::unique_ptr<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        auto *item = qobject_cast<QQuickItem *>(object.get());
        QVERIFY(item);
        view.resize(64, 64);
        item->setParentItem(view.contentItem());
        view.show();
        const int before = TelamonNetwork::refusedCount();
        QTest::qWait(1500);
        const int refused = TelamonNetwork::refusedCount() - before;
        // Nothing went out; an item that asks again gets one refusal a second, not a loop.
        QVERIFY2(refused <= 5, qPrintable(QStringLiteral("%1 refusals in 1.5 s").arg(refused)));
    }

    // An app's own factory is not replaced.
    void appFactoryWins()
    {
        struct Mine : QQmlNetworkAccessManagerFactory {
            QNetworkAccessManager *create(QObject *parent) override { return new QNetworkAccessManager(parent); }
        } mine;
        QQmlEngine engine;
        engine.setNetworkAccessManagerFactory(&mine);
        TelamonNetwork::install(&engine);
        QCOMPARE(engine.networkAccessManagerFactory(), &mine);
        QQmlEngine other;
        TelamonNetwork::install(&other);
        QVERIFY(other.networkAccessManagerFactory());
        QVERIFY(other.networkAccessManagerFactory() != &mine);
        TelamonNetwork::install(nullptr);
    }
};

QTEST_MAIN(TestNetwork)
#include "tst_network.moc"
