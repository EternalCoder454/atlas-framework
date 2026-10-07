// TelamonApp: what an About page needs to know, read-only. The running app
// (name, id, version, and its repository under github.com/EternalCoder454/)
// and the OS (from os-release), plus the Qt version in use.
//
// The app's startup code names its repository by setting the `telamonRepo`
// property on the application object, e.g.
// `app.setProperty("telamonRepo", "atlasos-updater")`. Without it, `repo`,
// `sourceUrl` and `issuesUrl` are empty. A name with anything but letters,
// digits, `.`, `_` or `-` counts as no name.
//
// `uiVersion` is the version of Telamon.Ui itself ("2.0.0"), from the project
// version at build time. Apps name the oldest they work with (`ui:` in
// telamon_framework_ui::app!) and the startup checks it. A Telamon.Ui without
// one is one the startup check cannot trust.
//
// os-release is read once, from /etc/os-release, else /usr/lib/os-release.
// Nothing in the environment changes which file. TelamonAboutPage shows it all.
#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class TelamonApp : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonApp)
    QML_SINGLETON

    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString repo READ repo CONSTANT)
    Q_PROPERTY(QString sourceUrl READ sourceUrl CONSTANT)
    Q_PROPERTY(QString issuesUrl READ issuesUrl CONSTANT)
    Q_PROPERTY(QString osName READ osName CONSTANT)
    Q_PROPERTY(QString osVersion READ osVersion CONSTANT)
    Q_PROPERTY(QString osPrettyName READ osPrettyName CONSTANT)
    Q_PROPERTY(QString osLogo READ osLogo CONSTANT)
    Q_PROPERTY(QString osHomeUrl READ osHomeUrl CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString uiVersion READ uiVersion CONSTANT)

public:
    explicit TelamonApp(QObject *parent = nullptr);

    QString name() const { return m_name; }
    QString id() const { return m_id; }
    QString version() const { return m_version; }
    QString repo() const { return m_repo; }
    QString sourceUrl() const { return m_sourceUrl; }
    QString issuesUrl() const { return m_issuesUrl; }
    QString osName() const { return m_osName; }
    QString osVersion() const { return m_osVersion; }
    QString osPrettyName() const { return m_osPrettyName; }
    QString osLogo() const { return m_osLogo; }
    QString osHomeUrl() const { return m_osHomeUrl; }
    QString qtVersion() const { return m_qtVersion; }
    QString uiVersion() const;

private:
    QString m_name, m_id, m_version, m_repo, m_sourceUrl, m_issuesUrl;
    QString m_osName, m_osVersion, m_osPrettyName, m_osLogo, m_osHomeUrl;
    QString m_qtVersion;
};
