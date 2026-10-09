// What the QML engines that load Telamon.Ui may fetch. Qt Quick fetches on
// its own: an Image, an AnimatedImage and a Kirigami.Icon given an address
// load it, and a Text in rich text loads the pictures it names. When the
// address comes from outside (a model row, a link in some metadata), that is a
// request made for whoever wrote it. The plugin gives each engine that has no
// network access manager factory of its own one that refuses cleartext
// addresses (http:, ftp:) except on this computer (localhost, 127.0.0.0/8,
// ::1), and limits redirects and the time a transfer may take. https: loads as
// before. Internal to the module (not installed).
#pragma once

#include <QNetworkAccessManager>
#include <QQmlEngine>
#include <QQmlNetworkAccessManagerFactory>
#include <QUrl>

#include <atomic>

namespace TelamonNetwork
{
// Whether a request for `url` may go out: not a cleartext address of another computer.
bool allowed(const QUrl &url);

// How many requests were refused in this process (for tests).
int refusedCount();

// The access manager the engines get. Created per thread by Qt Quick.
class AccessManager : public QNetworkAccessManager
{
public:
    explicit AccessManager(QObject *parent = nullptr);

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoing = nullptr) override;
};

class Factory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override;
};

// Sets the factory on `engine` unless the app already gave it one.
void install(QQmlEngine *engine);
}
