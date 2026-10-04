// Loads Atlas.Ui's own translations (atlas-ui_<locale>.qm) once, when the
// plugin library loads, so the qsTr() strings of the module's QML files show
// in the user's language without the app doing anything. The files come from
// the atlas-ui data directory; a development build also looks in the build
// tree, and ATLAS_UI_TRANSLATIONS_DIR overrides that.
//
// The language is chosen once per process, from QLocale at the first load; a
// later change of the system language shows after the app restarts.
#include <QCoreApplication>
#include <QDir>
#include <QLocale>
#include <QLoggingCategory>
#include <QMetaObject>
#include <QMutex>
#include <QStringList>
#include <QThread>
#include <QTranslator>
#include <QtGlobal>

#ifndef ATLAS_UI_TRANSLATIONS_DIR
#error "ATLAS_UI_TRANSLATIONS_DIR (the installed translations directory) must be defined by CMake"
#endif

namespace {

Q_LOGGING_CATEGORY(lcTranslations, "atlas.ui.translations")

// Whether the install has been started (on its way to the application's
// thread, or running there) or is done.
QMutex mutex;
enum class State { None, Started, Done } state = State::None;

void markDone()
{
    QMutexLocker lock(&mutex);
    state = State::Done;
}

// When the application object goes, so does the translator it owned: a later
// application in the same process (some tests make one) installs again.
void reset()
{
    QMutexLocker lock(&mutex);
    state = State::None;
}

// Runs on the application's thread, which owns the translator.
void installNow()
{
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

// Installs once, on the application's thread, whichever thread asks first (the
// QML engine may load the plugin off the main thread). Does nothing until the
// application object exists, and then the first caller has it done. True when
// the translator is in place on return; false when the install is still to
// run on the application's thread (anything queued there after this call runs
// after it).
bool installTranslations()
{
    QCoreApplication *app = QCoreApplication::instance();
    if (!app) {
        return false;
    }
    const bool here = QThread::currentThread() == app->thread();
    {
        QMutexLocker lock(&mutex);
        if (state != State::None) {
            return state == State::Done;
        }
        state = State::Started;
        qAddPostRoutine(reset);
        if (!here) {
            // Queued, not blocking: the application's thread may itself be
            // waiting on this one (an engine loading on a worker thread), and
            // a blocking call would deadlock. Posted under the lock, so that
            // whoever sees Started finds the install already queued.
            QMetaObject::invokeMethod(app, [] { installNow(); markDone(); }, Qt::QueuedConnection);
            return false;
        }
    }
    installNow();
    markDone();
    return true;
}

// Runs when the application object exists.
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
bool atlasUiInstallTranslations()
{
    return installTranslations();
}

// Whether the translator is in place (or there is none for this language).
bool atlasUiTranslationsDone()
{
    QMutexLocker lock(&mutex);
    return state == State::Done;
}

Q_COREAPP_STARTUP_FUNCTION(startup)
