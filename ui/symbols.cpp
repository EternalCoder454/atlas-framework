#include "symbols.h"

#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QLoggingCategory>
#include <QMetaEnum>

#include <algorithm>
#include <cstring>
#include <iterator>

namespace
{
Q_LOGGING_CATEGORY(lcSymbols, "atlas.ui.symbols")

struct Entry {
    const char *name;
    int codepoint;
    bool alias;
};

// Sorted by name (byte order), so lookups are a binary search.
constexpr Entry table[] = {
#include "symbols/symboltable.inc"
};

constexpr const char *styles[] = {"Outlined", "Rounded", "Sharp"};

QMetaEnum nameEnum()
{
    return QMetaEnum::fromType<SymbolNames::Name>();
}

const Entry *find(const QByteArray &name)
{
    const auto it = std::lower_bound(std::begin(table), std::end(table), name.constData(), [](const Entry &e, const char *n) {
        return std::strcmp(e.name, n) < 0;
    });
    return it != std::end(table) && std::strcmp(it->name, name.constData()) == 0 ? it : nullptr;
}

const Entry *findCanonical(int codepoint)
{
    for (const Entry &e : table) {
        if (e.codepoint == codepoint && !e.alias) {
            return &e;
        }
    }
    return nullptr;
}
}

Symbols::Symbols(QObject *parent)
    : QObject(parent)
{
    loadFonts();
}

void Symbols::loadFonts()
{
    static bool done = false;
    if (done) {
        return;
    }
    done = true;

    const QStringList installed = QFontDatabase::families();
    QStringList dirs;
#ifdef ATLAS_UI_SYMBOLS_SOURCE_DIR
    // Development builds only: a packaged Atlas.Ui is loaded into every Atlas
    // app, and must not parse a font file named by its environment.
    if (const QString env = qEnvironmentVariable("ATLAS_UI_SYMBOLS_DIR"); !env.isEmpty()) {
        dirs << env;
    }
    dirs << QStringLiteral(ATLAS_UI_SYMBOLS_SOURCE_DIR);
#endif
    for (const char *style : styles) {
        const QString family = QLatin1String("Material Symbols ") + QLatin1String(style);
        if (installed.contains(family)) {
            continue;
        }
        bool loaded = false;
        for (const QString &dir : std::as_const(dirs)) {
            const QString file = QDir(dir).filePath(QLatin1String("MaterialSymbols") + QLatin1String(style) + QLatin1String(".ttf"));
            if (QFileInfo::exists(file) && QFontDatabase::addApplicationFont(file) >= 0) {
                loaded = true;
                break;
            }
        }
        if (!loaded) {
            qCWarning(lcSymbols) << family << "is not installed (atlas-symbols-fonts): its symbols will be blank";
        }
    }
}

int Symbols::lookup(QStringView name)
{
    QByteArray key = name.toUtf8().trimmed().toLower();
    key.replace('-', '_').replace(' ', '_');
    if (const Entry *e = find(key)) {
        return e->codepoint;
    }
    // Symbols.ArrowBack's key, as a string.
    bool ok = false;
    const int value = nameEnum().keyToValue(name.toUtf8().constData(), &ok);
    return ok ? value : 0;
}

int Symbols::codepoint(const QString &name) const
{
    const int cp = lookup(name);
    if (cp == 0 && !name.isEmpty()) {
        qCWarning(lcSymbols) << "no symbol named" << name;
    }
    return cp;
}

QString Symbols::name(int codepoint) const
{
    const Entry *e = findCanonical(codepoint);
    return e ? QString::fromLatin1(e->name) : QString();
}

QString Symbols::key(int codepoint) const
{
    return QString::fromLatin1(nameEnum().valueToKey(codepoint));
}

QStringList Symbols::names() const
{
    QStringList out;
    out.reserve(std::size(table));
    for (const Entry &e : table) {
        if (!e.alias) {
            out << QString::fromLatin1(e.name);
        }
    }
    return out;
}

QString Symbols::family(int style) const
{
    const int i = style >= 0 && style < int(std::size(styles)) ? style : 1;
    return QLatin1String("Material Symbols ") + QLatin1String(styles[i]);
}
