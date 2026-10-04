#include "symbols.h"

#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QLoggingCategory>
#include <QMetaEnum>

#include <algorithm>
#include <atomic>
#include <mutex>
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
constexpr int Rounded = 1;

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

// The family of style `i` is installed, or (development builds) loaded from a
// source directory. Checked once per style, the first time it is needed.
bool Symbols::resolveStyle(int i)
{
    static std::once_flag once[std::size(styles)];
    static std::atomic<bool> ready[std::size(styles)];
    std::call_once(once[i], [i] {
        const QString family = QLatin1String("Material Symbols ") + QLatin1String(styles[i]);
        bool ok = QFontDatabase::hasFamily(family);
#ifdef ATLAS_UI_SYMBOLS_SOURCE_DIR
        // Development builds only: a packaged Atlas.Ui is loaded into every
        // Atlas app, and must not parse a font file named by its environment.
        QStringList dirs;
        if (const QString env = qEnvironmentVariable("ATLAS_UI_SYMBOLS_DIR"); !env.isEmpty()) {
            dirs << env;
        }
        dirs << QStringLiteral(ATLAS_UI_SYMBOLS_SOURCE_DIR);
        for (const QString &dir : std::as_const(dirs)) {
            if (ok) {
                break;
            }
            const QString file = QDir(dir).filePath(QLatin1String("MaterialSymbols") + QLatin1String(styles[i]) + QLatin1String(".ttf"));
            ok = QFileInfo::exists(file) && QFontDatabase::addApplicationFont(file) >= 0;
        }
#endif
        ready[i] = ok;
    });
    return ready[i];
}

void Symbols::loadFonts()
{
    static std::once_flag once;
    // Rounded is what Symbol draws with by default, so a missing one is a
    // broken install: say so now. Outlined and Sharp (atlas-symbols-fonts-extra)
    // are optional and are looked for when a Symbol first asks for them.
    std::call_once(once, [] {
        if (!resolveStyle(Rounded)) {
            qCWarning(lcSymbols) << "Material Symbols Rounded is not installed (atlas-symbols-fonts): its symbols will be blank";
        }
    });
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
    const int i = style >= 0 && style < int(std::size(styles)) ? style : Rounded;
    if (!resolveStyle(i)) {
        static std::once_flag warned[std::size(styles)];
        std::call_once(warned[i], [i] {
            if (i != Rounded) { // Rounded warned when the fonts loaded
                qCWarning(lcSymbols) << "Material Symbols" << styles[i] << "is not installed (atlas-symbols-fonts-extra): its symbols will be blank";
            }
        });
    }
    return QLatin1String("Material Symbols ") + QLatin1String(styles[i]);
}

bool Symbols::available(int style) const
{
    return style >= 0 && style < int(std::size(styles)) && resolveStyle(style);
}
