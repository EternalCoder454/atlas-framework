// AtlasWindowChrome: what the desktop says about window decoration, for a
// frameless AtlasWindow that draws its own header (AtlasHeaderBar).
//
//   buttonsOnLeft / buttonsOnRight  KWin's caption button layout
//       (kwinrc [org.kde.kdecoration2] ButtonsOnLeft / ButtonsOnRight), as
//       lists of "menu", "minimize", "maximize" and "close", in KWin's order. Other
//       KWin buttons (help, pin, ...) are dropped. Defaults are AtlasOS's
//       (left: menu; right: minimize, maximize, close). A layout with none
//       of minimize, maximize and close falls back to the default, so a window
//       can always be closed. Follows kwinrc live.
//   globalMenu  the desktop has a global menu (an owner of the D-Bus name
//       com.canonical.AppMenu.Registrar, as Plasma's app menu widget has) and the
//       Qt platform theme is KDE's, so the export can work.
//       False until the first answer, which arrives asynchronously (a 1 s
//       timeout, so a stalled bus never blocks the UI); follows the name live.
#pragma once

#include <KConfigWatcher>
#include <KSharedConfig>

#include <QDBusServiceWatcher>
#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

class AtlasWindowChrome : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AtlasWindowChrome)
    QML_SINGLETON

    Q_PROPERTY(QStringList buttonsOnLeft READ buttonsOnLeft NOTIFY buttonsChanged)
    Q_PROPERTY(QStringList buttonsOnRight READ buttonsOnRight NOTIFY buttonsChanged)
    Q_PROPERTY(bool globalMenu READ globalMenu NOTIFY globalMenuChanged)

public:
    explicit AtlasWindowChrome(QObject *parent = nullptr);

    QStringList buttonsOnLeft() const { return m_left; }
    QStringList buttonsOnRight() const { return m_right; }
    bool globalMenu() const { return m_globalMenu; }

    // Parses a KWin button string ("MS", "HIAX") into button names. Pure, for
    // tests: unknown letters are dropped, repeats are kept once.
    Q_INVOKABLE static QStringList _parseButtons(const QString &letters);

Q_SIGNALS:
    void buttonsChanged();
    void globalMenuChanged();

private:
    void readButtons();
    void checkGlobalMenu();
    void setRegistrar(bool owned);

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    QDBusServiceWatcher *m_serviceWatcher = nullptr;
    QStringList m_left;
    QStringList m_right;
    bool m_globalMenu = false;
    bool m_ownerKnown = false;
};
