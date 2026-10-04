// apidump: prints the public API of the built Atlas.Ui module, one sorted line
// per item, for tools/check-api.sh to compare with api/ in the repository.
//
//   apidump <qml-root> <atlas-ui.api> <symbols.txt>
//
// <qml-root> is the directory holding Atlas/Ui (the build directory). For every
// type in the module's qmldir and every creatable or singleton type in its
// qmltypes file, the tool makes one instance (a singleton is read; nothing is
// shown) and walks the instance's QMetaObject chain while the classes belong to
// Atlas.Ui: QML-defined types ("_QMLTYPE_" in the class name) and the C++ classes
// named in the qmltypes file.
//
//   Type.property name: type [readonly]
//   Type.signal name(type name, ...)
//   Type.method name(type name, ...): returnType
//   Type.enum Name: Value = number          (one line per value, so a new value
//                                            reads as an addition, not a change)
//
// The Symbols names (thousands of lines) go to <symbols.txt>.
#include <QApplication>
#include <QDir>
#include <QFile>
#include <QMetaMethod>
#include <QMetaObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QTextStream>

#include <cstdio>
#include <cstdlib>

namespace {

struct QmlTypesComponent {
    QString name;
    QStringList exportedNames;
    bool singleton = false;
    bool creatable = true;
};

QString readFile(const QString &path, QString *error)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *error = QStringLiteral("cannot read %1: %2").arg(path, file.errorString());
        return {};
    }
    return QString::fromUtf8(file.readAll());
}

// The qmltypes file is regular enough (one key per line, written by Qt's own
// tool) to read line by line; the tool fails if it finds no Component at all.
QList<QmlTypesComponent> parseQmlTypes(const QString &text)
{
    QList<QmlTypesComponent> components;
    static const QRegularExpression nameLine(QStringLiteral("^\\s*name:\\s*\"([^\"]+)\""));
    static const QRegularExpression exportsLine(QStringLiteral("^\\s*exports:\\s*\\[(.*)\\]"));
    static const QRegularExpression quoted(QStringLiteral("\"([^\"]+)\"(?:\\s*:\\s*(-?\\d+))?"));
    for (const QString &line : text.split(QLatin1Char('\n'))) {
        const QString trimmed = line.trimmed();
        if (trimmed == QLatin1String("Component {")) {
            components.append(QmlTypesComponent{});
            continue;
        }
        if (components.isEmpty()) {
            continue;
        }
        QmlTypesComponent &c = components.last();
        if (auto m = nameLine.match(line); m.hasMatch() && c.name.isEmpty()) {
            c.name = m.captured(1);
        } else if (auto e = exportsLine.match(line); e.hasMatch()) {
            for (auto it = quoted.globalMatch(e.captured(1)); it.hasNext();) {
                // "Atlas.Ui/LiveChartItem 1.0"
                const QString exported = it.next().captured(1);
                c.exportedNames << exported.section(QLatin1Char('/'), 1).section(QLatin1Char(' '), 0, 0);
            }
        } else if (trimmed == QLatin1String("isSingleton: true")) {
            c.singleton = true;
        } else if (trimmed == QLatin1String("isCreatable: false")) {
            c.creatable = false;
        }
    }
    return components;
}

QString typeName(const QByteArray &name)
{
    return name.isEmpty() ? QStringLiteral("void") : QString::fromLatin1(name);
}

QString signature(const QMetaMethod &m)
{
    QStringList params;
    const QList<QByteArray> names = m.parameterNames();
    for (int i = 0; i < m.parameterCount(); ++i) {
        const QByteArray type = QMetaType(m.parameterType(i)).name() ? QByteArray(QMetaType(m.parameterType(i)).name()) : m.parameterTypeName(i);
        params << (typeName(type) + (i < names.size() && !names[i].isEmpty() ? QLatin1Char(' ') + QString::fromLatin1(names[i]) : QString()));
    }
    return QStringLiteral("%1(%2)").arg(QString::fromLatin1(m.name()), params.join(QStringLiteral(", ")));
}

void addEnum(QStringList &lines, const QString &type, const QString &name, const QStringList &values)
{
    for (const QString &value : values) {
        lines << QStringLiteral("%1.enum %2: %3").arg(type, name, value);
    }
}

void dumpMetaObject(const QString &type, const QMetaObject *start, const QSet<QString> &atlasClasses, QStringList &lines)
{
    for (const QMetaObject *mo = start; mo; mo = mo->superClass()) {
        const QString className = QString::fromLatin1(mo->className());
        if (!className.contains(QLatin1String("_QMLTYPE_")) && !atlasClasses.contains(className)) {
            break;
        }
        QSet<QByteArray> notifySignals;
        for (int i = mo->propertyOffset(); i < mo->propertyCount(); ++i) {
            const QMetaProperty p = mo->property(i);
            lines << QStringLiteral("%1.property %2: %3%4")
                         .arg(type, QString::fromLatin1(p.name()), typeName(p.typeName()), p.isWritable() ? QString() : QStringLiteral(" [readonly]"));
            if (p.hasNotifySignal()) {
                notifySignals.insert(p.notifySignal().methodSignature());
            }
        }
        for (int i = mo->methodOffset(); i < mo->methodCount(); ++i) {
            const QMetaMethod m = mo->method(i);
            if (m.access() != QMetaMethod::Public || m.methodType() == QMetaMethod::Constructor || m.name().startsWith("_q_")) {
                continue;
            }
            if (m.methodType() == QMetaMethod::Signal) {
                // Generated: the property's own line already says it exists.
                if (!notifySignals.contains(m.methodSignature())) {
                    lines << QStringLiteral("%1.signal %2").arg(type, signature(m));
                }
            } else {
                lines << QStringLiteral("%1.method %2: %3").arg(type, signature(m), typeName(m.typeName()));
            }
        }
        for (int i = mo->enumeratorOffset(); i < mo->enumeratorCount(); ++i) {
            const QMetaEnum e = mo->enumerator(i);
            QStringList values;
            for (int k = 0; k < e.keyCount(); ++k) {
                values << QStringLiteral("%1 = %2").arg(QString::fromLatin1(e.key(k))).arg(e.value(k));
            }
            addEnum(lines, type, QString::fromLatin1(e.name()), values);
        }
    }
}

bool writeLines(const QString &path, QStringList lines)
{
    lines.sort();
    lines.removeDuplicates();
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        std::fprintf(stderr, "apidump: cannot write %s: %s\n", qPrintable(path), qPrintable(file.errorString()));
        return false;
    }
    file.write(lines.join(QLatin1Char('\n')).toUtf8());
    file.write("\n");
    if (!file.commit()) {
        std::fprintf(stderr, "apidump: cannot write %s: %s\n", qPrintable(path), qPrintable(file.errorString()));
        return false;
    }
    return true;
}

} // namespace

int main(int argc, char *argv[])
{
    qputenv("QT_QPA_PLATFORM", qgetenv("QT_QPA_PLATFORM").isEmpty() ? QByteArray("offscreen") : qgetenv("QT_QPA_PLATFORM"));
    qputenv("QT_QUICK_BACKEND", "software");
    QApplication app(argc, argv);
    if (argc != 4) {
        std::fprintf(stderr, "usage: apidump <qml-root> <atlas-ui.api> <symbols.txt>\n");
        return 2;
    }
    const QString root = QDir(QString::fromLocal8Bit(argv[1])).absolutePath();
    const QString moduleDir = root + QStringLiteral("/Atlas/Ui");

    QString error;
    const QString qmldir = readFile(moduleDir + QStringLiteral("/qmldir"), &error);
    if (qmldir.isEmpty()) {
        std::fprintf(stderr, "apidump: %s\n", qPrintable(error));
        return 1;
    }
    QString typesFile = QStringLiteral("atlasui.qmltypes");
    QStringList qmlTypeNames; // QML-defined, from the qmldir
    for (const QString &line : qmldir.split(QLatin1Char('\n'))) {
        const QStringList words = line.simplified().split(QLatin1Char(' '));
        if (words.value(0) == QLatin1String("typeinfo")) {
            typesFile = words.value(1);
        } else if (words.size() >= 3 && words.last().endsWith(QLatin1String(".qml")) && words.value(0) != QLatin1String("internal")) {
            const QString name = words.value(0) == QLatin1String("singleton") ? words.value(1) : words.value(0);
            qmlTypeNames << name;
        }
    }
    const QList<QmlTypesComponent> components = parseQmlTypes(readFile(moduleDir + QLatin1Char('/') + typesFile, &error));
    if (components.isEmpty()) {
        std::fprintf(stderr, "apidump: no types in %s %s\n", qPrintable(typesFile), qPrintable(error));
        return 1;
    }

    QSet<QString> atlasClasses;
    for (const QmlTypesComponent &c : components) {
        atlasClasses.insert(c.name);
    }
    // The type names to dump: QML-defined from the qmldir, C++ from the exports.
    QSet<QString> typeNames(qmlTypeNames.begin(), qmlTypeNames.end());
    QHash<QString, const QmlTypesComponent *> cppTypes;
    for (const QmlTypesComponent &c : components) {
        for (const QString &exported : c.exportedNames) {
            if (!typeNames.contains(exported)) {
                cppTypes.insert(exported, &c);
            }
        }
    }

    QQmlEngine engine;
    engine.addImportPath(root);
    QStringList lines;
    QStringList symbolLines;
    int failures = 0;

    const auto instance = [&](const QString &name, bool singleton) -> QObject * {
        QQmlComponent component(&engine);
        const QByteArray source = singleton ? QByteArray("import QtQml\nimport Atlas.Ui\nQtObject { property var v: ") + name.toUtf8() + " }"
                                            : QByteArray("import QtQuick\nimport Atlas.Ui\n") + name.toUtf8() + " {}";
        component.setData(source, QUrl(QStringLiteral("file:///apidump/%1.qml").arg(name)));
        if (component.isError()) {
            std::fprintf(stderr, "apidump: cannot load %s: %s\n", qPrintable(name), qPrintable(component.errorString()));
            return nullptr;
        }
        // beginCreate only: no Component.onCompleted, no required-property check,
        // and the object is never shown. It is leaked on purpose (see main's end).
        // A singleton is read through a binding, which needs a completed object.
        QObject *object = singleton ? component.create(engine.rootContext()) : component.beginCreate(engine.rootContext());
        if (!object) {
            std::fprintf(stderr, "apidump: cannot create %s: %s\n", qPrintable(name), qPrintable(component.errorString()));
            return nullptr;
        }
        if (singleton) {
            QObject *value = qvariant_cast<QObject *>(object->property("v"));
            if (!value) {
                std::fprintf(stderr, "apidump: %s is not an object\n", qPrintable(name));
            }
            return value;
        }
        return object;
    };

    QStringList all = QStringList(typeNames.begin(), typeNames.end()) + QStringList(cppTypes.keyBegin(), cppTypes.keyEnd());
    all.sort();
    for (const QString &name : std::as_const(all)) {
        const QmlTypesComponent *cpp = cppTypes.value(name);
        const QmlTypesComponent *qml = nullptr;
        for (const QmlTypesComponent &c : components) {
            if (c.exportedNames.contains(name)) {
                qml = &c; // QML singletons and types also appear in the qmltypes
            }
        }
        const bool singleton = (cpp && cpp->singleton) || (qml && qml->singleton);
        if (cpp && !cpp->creatable && !singleton) {
            std::fprintf(stderr, "apidump: %s is not creatable and not a singleton; skipped\n", qPrintable(name));
            continue;
        }
        QObject *object = instance(name, singleton);
        if (!object) {
            ++failures;
            continue;
        }
        QStringList typeLines;
        dumpMetaObject(name, object->metaObject(), atlasClasses, typeLines);
        // The Symbols names are thousands of lines: their own file.
        if (name == QLatin1String("Symbols")) {
            const QString prefix = QStringLiteral("Symbols.enum Name: ");
            for (auto it = typeLines.begin(); it != typeLines.end();) {
                if (it->startsWith(prefix)) {
                    symbolLines << *it;
                    it = typeLines.erase(it);
                } else {
                    ++it;
                }
            }
        }
        lines += typeLines;
        // Every type is listed, even one that adds nothing to its Qt base.
        lines << QStringLiteral("%1.type").arg(name);
    }
    if (failures) {
        std::fprintf(stderr, "apidump: %d type(s) failed\n", failures);
        return 1;
    }
    if (!writeLines(QString::fromLocal8Bit(argv[2]), lines) || !writeLines(QString::fromLocal8Bit(argv[3]), symbolLines)) {
        return 1;
    }
    std::fflush(nullptr);
    // Objects made with beginCreate are never completed; tearing them down
    // is not worth a crash that would fail the check.
    std::quick_exit(0);
}
