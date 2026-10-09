#include "telamonnetwork.h"

#include "telamonlogsafe.h"

#include <QHostAddress>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlEngine>
#include <QTimer>

namespace TelamonNetwork
{
namespace
{
std::atomic<int> s_refused{0};
// A transfer that has not finished by then is given up.
constexpr int kTransferTimeoutMs = 60 * 1000;
constexpr int kMaxRedirects = 5;
// How long a refused request takes to fail.
constexpr int kRefusalDelayMs = 1000;

// The reply to a request that is refused: an error at once, nothing sent.
class RefusedReply : public QNetworkReply
{
public:
    RefusedReply(const QNetworkRequest &request, QNetworkAccessManager::Operation op, QObject *parent)
        : QNetworkReply(parent)
    {
        setRequest(request);
        setUrl(request.url());
        setOperation(op);
        setError(QNetworkReply::ContentAccessDenied, QStringLiteral("Telamon.Ui does not fetch cleartext addresses (use https)"));
        open(QIODevice::ReadOnly | QIODevice::Unbuffered);
        // Not at once: Kirigami.Icon asks again whenever a fetch fails, and an
        // instant error makes it ask a hundred times a second.
        QTimer::singleShot(kRefusalDelayMs, this, [this] {
            Q_EMIT errorOccurred(QNetworkReply::ContentAccessDenied);
            setFinished(true);
            Q_EMIT finished();
        });
    }
    void abort() override
    {
    }

protected:
    qint64 readData(char *, qint64) override
    {
        return -1;
    }
};
}

bool allowed(const QUrl &url)
{
    const QString scheme = url.scheme().toLower();
    if (scheme != QLatin1String("http") && scheme != QLatin1String("ftp")) {
        return true;
    }
    QString host = url.host().toLower();
    if (host.endsWith(QLatin1Char('.'))) {
        host.chop(1);
    }
    if (host == QLatin1String("localhost")) {
        return true;
    }
    QHostAddress address;
    return address.setAddress(host) && address.isLoopback();
}

int refusedCount()
{
    return s_refused;
}

AccessManager::AccessManager(QObject *parent)
    : QNetworkAccessManager(parent)
{
}

QNetworkReply *AccessManager::createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoing)
{
    if (!allowed(request.url())) {
        // One line is enough: Kirigami and Qt Quick ask again for a failed address.
        if (s_refused.fetch_add(1) == 0) {
            qWarning("Telamon.Ui: not fetching %s://%s: only https addresses are fetched (the first refusal of this process; the others are not logged)",
                     qPrintable(logSafe(request.url().scheme().left(16))),
                     qPrintable(logSafe(request.url().host().left(100))));
        }
        return new RefusedReply(request, op, this);
    }
    QNetworkRequest limited(request);
    // A redirect to a less safe address (https to http) is not followed. (An
    // http address on this computer that redirects to another computer's http
    // address is: the first request is the app's own to a local server.)
    limited.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    limited.setMaximumRedirectsAllowed(kMaxRedirects);
    if (limited.transferTimeout() == 0) {
        limited.setTransferTimeout(kTransferTimeoutMs);
    }
    return QNetworkAccessManager::createRequest(op, limited, outgoing);
}

QNetworkAccessManager *Factory::create(QObject *parent)
{
    return new AccessManager(parent);
}

void install(QQmlEngine *engine)
{
    static Factory factory;
    if (engine && !engine->networkAccessManagerFactory()) {
        engine->setNetworkAccessManagerFactory(&factory);
    }
}
}
