// Finds the gallery demos (ui/gallery/demos/*Demo.qml) at run time, for the
// Qt Quick tests that run over all of them (visual/, a11y/). Reads
// TELAMON_DEMO_DIR (required) and TELAMON_DEMO_FILTER (regular expression on the
// demo name without "Demo").
#pragma once

#include <QDir>
#include <QFile>
#include <QObject>
#include <QRegularExpression>
#include <QUrl>

class DemoList : public QObject
{
    Q_OBJECT
public:
    // The demo names, sorted, minus the "Demo" suffix.
    Q_INVOKABLE QStringList demos() const
    {
        const QDir dir(qEnvironmentVariable("TELAMON_DEMO_DIR"));
        const QString pattern = qEnvironmentVariable("TELAMON_DEMO_FILTER");
        const QRegularExpression filter(pattern.isEmpty() ? QStringLiteral(".*") : pattern);
        QStringList names;
        const QStringList files = dir.entryList({QStringLiteral("*Demo.qml")}, QDir::Files, QDir::Name);
        for (const QString &file : files) {
            const QString name = file.chopped(int(sizeof("Demo.qml") - 1));
            if (filter.match(name).hasMatch()) {
                names << name;
            }
        }
        return names;
    }

    Q_INVOKABLE QUrl demoUrl(const QString &name) const
    {
        return QUrl::fromLocalFile(QDir(qEnvironmentVariable("TELAMON_DEMO_DIR")).filePath(name + QStringLiteral("Demo.qml")));
    }

    // True when the demo's root element is a window (TelamonWindowDemo).
    Q_INVOKABLE bool rootIsWindow(const QString &name) const
    {
        QFile file(QDir(qEnvironmentVariable("TELAMON_DEMO_DIR")).filePath(name + QStringLiteral("Demo.qml")));
        if (!file.open(QIODevice::ReadOnly)) {
            return false;
        }
        static const QRegularExpression root(QStringLiteral("^(?:[A-Za-z0-9_]+\\.)?[A-Za-z0-9_]*Window\\s*\\{"),
                                             QRegularExpression::MultilineOption);
        return root.match(QString::fromUtf8(file.readAll())).hasMatch();
    }
};
