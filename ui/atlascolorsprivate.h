// AtlasColorsPrivate: the C++ behind AtlasStyle.alpha() and AtlasStyle.mix().
// Qt.alpha and Qt.rgba return a QVariant, which keeps a binding out of the
// AOT-compiled code; a QColor-typed call keeps it in. Not API: apps call
// AtlasStyle.alpha() and AtlasStyle.mix() (docs/reference/atlas-ui/atlas-style.md,
// which also says how NaN, out-of-range and invalid colours are handled).
// tools/apidump leaves types whose name ends in "Private" out of api/.
#pragma once

#include <QColor>
#include <QObject>
#include <QtQml/qqmlregistration.h>

class AtlasColorsPrivate : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(AtlasColorsPrivate)
    QML_SINGLETON

public:
    explicit AtlasColorsPrivate(QObject *parent = nullptr);

    // `c` with alpha `a` (clamped to 0..1, NaN is 0). Invalid in, invalid out.
    Q_INVOKABLE QColor alpha(const QColor &c, double a) const;
    // `a` blended toward `b` by `t` (clamped to 0..1, NaN is 0), linearly in
    // sRGB, alpha included. Either colour invalid gives an invalid colour.
    Q_INVOKABLE QColor mix(const QColor &a, const QColor &b, double t) const;
};
