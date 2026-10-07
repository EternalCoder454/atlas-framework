// The Telamon validators: QValidators for a text field's `validator`, so a
// TelamonTextField (with `invalidText`) can say what is wrong with what was typed.
// Acceptable means the text is a complete valid value; Intermediate means it
// can still become one (the user is typing); Invalid means no continuation
// helps, so the character is not accepted. Every one of them rejects text
// longer than a fixed bound (no work grows with hostile input), looks at it
// without regular expressions, and rejects NUL and other control characters.
//
//   TelamonTextField {
//       validator: TelamonUrlValidator { schemes: ["https"] }
//       invalidText: qsTr("Enter a web address starting with https://")
//   }
#pragma once

#include <QDoubleValidator>
#include <QStringList>
#include <QValidator>
#include <QtQml/qqmlregistration.h>

// A URL with one of `schemes`; http and https also need a host.
class TelamonUrlValidator : public QValidator
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonUrlValidator)

    Q_PROPERTY(QStringList schemes READ schemes WRITE setSchemes NOTIFY schemesChanged FINAL)

public:
    explicit TelamonUrlValidator(QObject *parent = nullptr);

    QStringList schemes() const { return m_schemes; }
    void setSchemes(const QStringList &schemes);

    State validate(QString &input, int &pos) const override;
    // Trims surrounding whitespace.
    void fixup(QString &input) const override;

Q_SIGNALS:
    void schemesChanged();

private:
    QStringList m_schemes;
};

// A pragmatic address: one @, a local part, a domain with a dot.
class TelamonEmailValidator : public QValidator
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonEmailValidator)

public:
    explicit TelamonEmailValidator(QObject *parent = nullptr);

    State validate(QString &input, int &pos) const override;
    void fixup(QString &input) const override;
};

// A file path; "~" and "~/" stand for the home directory. With `mustExist`
// every validate() call (so every keystroke) stats the path on disk: leave it
// off for paths on slow or network file systems.
class TelamonPathValidator : public QValidator
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonPathValidator)

    Q_PROPERTY(bool absolute READ absolute WRITE setAbsolute NOTIFY absoluteChanged FINAL)
    Q_PROPERTY(bool mustExist READ mustExist WRITE setMustExist NOTIFY mustExistChanged FINAL)
    Q_PROPERTY(bool directory READ directory WRITE setDirectory NOTIFY directoryChanged FINAL)

public:
    explicit TelamonPathValidator(QObject *parent = nullptr);

    bool absolute() const { return m_absolute; }
    void setAbsolute(bool on);
    bool mustExist() const { return m_mustExist; }
    void setMustExist(bool on);
    bool directory() const { return m_directory; }
    void setDirectory(bool on);

    State validate(QString &input, int &pos) const override;

Q_SIGNALS:
    void absoluteChanged();
    void mustExistChanged();
    void directoryChanged();

private:
    bool m_absolute = true;
    bool m_mustExist = false;
    bool m_directory = false;
};

// A number between `bottom` and `top` with at most `decimals` decimals (default
// 15, the most; set 0 for whole numbers), written the way the validator's
// locale writes numbers (group separators accepted). fixup() drops a trailing
// decimal point and clamps a number to `bottom`/`top`.
class TelamonNumberValidator : public QValidator
{
    Q_OBJECT
    QML_NAMED_ELEMENT(TelamonNumberValidator)

    Q_PROPERTY(qreal bottom READ bottom WRITE setBottom NOTIFY bottomChanged FINAL)
    Q_PROPERTY(qreal top READ top WRITE setTop NOTIFY topChanged FINAL)
    Q_PROPERTY(int decimals READ decimals WRITE setDecimals NOTIFY decimalsChanged FINAL)
    // A locale name such as "de_DE"; empty (the default) is the application's locale.
    Q_PROPERTY(QString locale READ localeName WRITE setLocaleName NOTIFY localeNameChanged FINAL)

public:
    explicit TelamonNumberValidator(QObject *parent = nullptr);

    qreal bottom() const { return m_bottom; }
    void setBottom(qreal bottom);
    qreal top() const { return m_top; }
    void setTop(qreal top);
    int decimals() const { return m_decimals; }
    void setDecimals(int decimals);
    QString localeName() const { return locale().name(); }
    void setLocaleName(const QString &name);

    State validate(QString &input, int &pos) const override;
    void fixup(QString &input) const override;

Q_SIGNALS:
    void bottomChanged();
    void topChanged();
    void decimalsChanged();
    void localeNameChanged();

private:
    // A QDoubleValidator configured for each call: it knows the locale rules.
    void configure(QDoubleValidator &inner) const;

    qreal m_bottom;
    qreal m_top;
    int m_decimals = 15;
};
