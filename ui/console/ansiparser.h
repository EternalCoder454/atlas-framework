// AnsiParser: the streaming parser behind TelamonConsoleView. It reads the text
// a command wrote (as UTF-16, in chunks of any size) and gives back plain text
// and style runs. It is pure (no QObject, no theme): colours leave as palette
// slots, and every escape sequence that is not a colour or a text style is
// dropped. See docs/reference/telamon-ui/telamon-console-view.md for the rules
// ("What is shown and what is dropped"). Not API: tools/apidump leaves out the
// types of ui/console that are not registered to QML.
#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringView>

namespace TelamonConsole {

// A line is cut after this many UTF-16 units; the rest goes on in a new line.
constexpr int MaxLineUnits = 4096;
// The most units an escape string (OSC, DCS, ...) may take before it is given up.
constexpr int MaxStringUnits = 4096;
// The most parameter and intermediate bytes of one CSI sequence.
constexpr int MaxCsiBytes = 64;
// The most parameters of one SGR sequence that are read.
constexpr int MaxSgrParams = 32;

// Colour slots: 0..7 the ANSI colours, 8..15 their bright variants, 16..23 a
// grey ramp from the muted text colour to the text colour. NoColor is the
// default colour.
constexpr quint8 NoColor = 0xFF;
constexpr int PaletteSlots = 24;

enum StyleFlag : quint8 {
    Bold = 1,
    Dim = 2,
    Italic = 4,
    Underline = 8,
    Inverse = 16,
    Strike = 32,
};

struct Style
{
    quint8 fg = NoColor;
    quint8 bg = NoColor;
    quint8 flags = 0;

    bool isDefault() const { return fg == NoColor && bg == NoColor && flags == 0; }
    friend bool operator==(const Style &a, const Style &b) { return a.fg == b.fg && a.bg == b.bg && a.flags == b.flags; }
    friend bool operator!=(const Style &a, const Style &b) { return !(a == b); }
};

// `length` units of the text from `start`, in one style. Never holds a newline;
// text in the default style has no run.
struct Run
{
    int start = 0;
    int length = 0;
    Style style;
};

// What one feed() produced. `text` and `runs` are added after the end of the
// text the view already has, unless `clearsLastLine`: then the view's last line
// is emptied first (a carriage return, then more text). A `\n` in `text` ends a
// line; the last line of `text` goes on the view's last line.
struct Parsed
{
    QString text;
    QList<Run> runs;
    bool clearsLastLine = false;
};

// The slot a 256-colour index (0..255) stands for.
quint8 slotFor256(int index);
// The slot an RGB colour (0..255 each) is approximated by: a grey from the
// ramp when it has little colour, else the nearest of the six hues, bright when
// light.
quint8 slotForRgb(int r, int g, int b);

class AnsiParser
{
public:
    // Reads `chunk` and adds what it shows to `out`. The state (an unfinished
    // escape sequence, the style, a carriage return, half a surrogate pair)
    // is kept for the next call.
    void feed(QStringView chunk, Parsed &out);
    // Back to the start: default style, nothing pending.
    void reset();

    Style style() const { return m_style; }

private:
    enum class State : quint8 {
        Ground,
        Esc,         // after ESC
        EscInter,    // ESC and an intermediate byte, waiting for the final one
        Csi,         // parameter bytes
        CsiInter,    // intermediate bytes
        CsiIgnore,   // a CSI that is wrong or too long: eaten up to its final byte
        String,      // OSC, DCS, SOS, PM, APC
        StringEsc,   // ESC inside a string
    };

    void step(char16_t c, Parsed &out);
    void ground(char16_t c, Parsed &out);
    void put(const char16_t *units, int count, Parsed &out);
    void newline(Parsed &out);
    void clearLine(Parsed &out);
    void sgr();
    void startCsi();
    void startString(bool osc);

    State m_state = State::Ground;
    Style m_style;
    char16_t m_high = 0;        // a high surrogate waiting for its low one
    bool m_cr = false;          // a carriage return is pending
    int m_col = 0;              // units on the view's last line
    int m_lastNewline = -1;     // index of the last '\n' in this call's text
    // CSI
    QByteArray m_csi;           // parameter bytes
    bool m_csiPrivate = false;  // a '<=>?' marker or an intermediate byte
    // strings
    bool m_stringOsc = false;
    int m_stringUnits = 0;
    int m_escInter = 0;
};

} // namespace TelamonConsole
