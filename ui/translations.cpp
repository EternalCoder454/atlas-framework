// Loads Atlas.Ui's own translations (atlas-ui_<locale>.qm) once, when the
// plugin library loads, so the qsTr() strings of the module's QML files show
// in the user's language without the app doing anything. The files come from
// the atlas-ui data directory; a development build also looks in the build
// tree, and ATLAS_UI_TRANSLATIONS_DIR overrides that.
#include <QCoreApplication>
#include <QDir>
#include <QLocale>
#include <QLoggingCategory>
#include <QMetaObject>
#include <QStringList>
#include <QTranslator>
#include <QtGlobal>

#ifndef ATLAS_UI_TRANSLATIONS_DIR
#error "ATLAS_UI_TRANSLATIONS_DIR (the installed translations directory) must be defined by CMake"
#endif

namespace {

Q_LOGGING_CATEGORY(lcTranslations, "atlas.ui.translations")

bool installed = false;

void installTranslations()
{
    if (installed || !QCoreApplication::instance()) {
        return;
    }
    installed = true;
    QStringList dirs;
#ifdef ATLAS_UI_TRANSLATIONS_BUILD_DIR
    // Development builds only: a packaged Atlas.Ui is loaded into every Atlas
    // app, and must not read a catalogue named by its environment or hold a
    // path into the build tree.
    if (const QString env = qEnvironmentVariable("ATLAS_UI_TRANSLATIONS_DIR"); !env.isEmpty()) {
        dirs << env;
    }
    dirs << QStringLiteral(ATLAS_UI_TRANSLATIONS_BUILD_DIR);
#endif
    dirs << QStringLiteral(ATLAS_UI_TRANSLATIONS_DIR);

    qCDebug(lcTranslations) << "looking for atlas-ui translations for" << QLocale().uiLanguages() << "in" << dirs;
    auto *translator = new QTranslator(QCoreApplication::instance());
    // The first directory with a catalogue for one of the user's languages wins.
    for (const QString &dir : std::as_const(dirs)) {
        if (QDir(dir).exists() && translator->load(QLocale(), QStringLiteral("atlas-ui"), QStringLiteral("_"), dir)) {
            qCDebug(lcTranslations) << "loaded" << translator->filePath();
            QCoreApplication::installTranslator(translator);
            return;
        }
    }
    // No catalogue for this language (English, or not translated yet): the
    // source strings are shown.
    delete translator;
}

// Runs when the application object exists. Done on the application's thread,
// which owns the translator.
void startup()
{
    QCoreApplication *app = QCoreApplication::instance();
    if (app) {
        QMetaObject::invokeMethod(app, [] { installTranslations(); }, Qt::AutoConnection);
    }
}

} // namespace

// Also called by the QML plugin as the module loads, which is before the
// startup function runs when a QML import loads this library (atlasuiplugin.cpp).
void atlasUiInstallTranslations()
{
    installTranslations();
}

Q_COREAPP_STARTUP_FUNCTION(startup)
