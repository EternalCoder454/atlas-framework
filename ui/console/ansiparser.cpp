#include "ansiparser.h"

#include <algorithm>
#include <cmath>

namespace TelamonConsole {

namespace {

constexpr char16_t Replacement = 0xFFFD;

bool isBidiOrInvisible(char16_t c)
{
    return c == 0x061C || (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E)
        || (c >= 0x2066 && c <= 0x2069) || c == 0xFEFF;
}

// One parameter group of an SGR sequence: the numbers between two ';', split at ':'.
// -1 is an empty number, -2 one that is too big.
struct Group
{
    int n = 0;
    int v[8] = {};
};

} // namespace

quint8 slotFor256(int index)
{
    if (index < 0 || index > 255) {
        return NoColor;
    }
    if (index < 16) {
        return quint8(index);
    }
    if (index >= 232) {
        const int g = 8 + 10 * (index - 232);
        return slotForRgb(g, g, g);
    }
    static const int level[6] = {0, 95, 135, 175, 215, 255};
    const int i = index - 16;
    return slotForRgb(level[i / 36], level[(i / 6) % 6], level[i % 6]);
}

quint8 slotForRgb(int r, int g, int b)
{
    r = std::clamp(r, 0, 255);
    g = std::clamp(g, 0, 255);
    b = std::clamp(b, 0, 255);
    const int hi = std::max({r, g, b});
    const int lo = std::min({r, g, b});
    const int chroma = hi - lo;
    const int sum = hi + lo; // 0..510
    if (chroma < 48) {
        return quint8(16 + int(std::lround(sum * 7.0 / 510.0)));
    }
    double h;
    if (hi == r) {
        h = 60.0 * ((g - b) / double(chroma));
    } else if (hi == g) {
        h = 60.0 * ((b - r) / double(chroma) + 2.0);
    } else {
        h = 60.0 * ((r - g) / double(chroma) + 4.0);
    }
    if (h < 0) {
        h += 360.0;
    }
    int slot;
    if (h < 30 || h >= 330) {
        slot = 1; // red
    } else if (h < 90) {
        slot = 3; // yellow
    } else if (h < 150) {
        slot = 2; // green
    } else if (h < 210) {
        slot = 6; // cyan
    } else if (h < 270) {
        slot = 4; // blue
    } else {
        slot = 5; // magenta
    }
    return quint8(sum >= 255 ? slot + 8 : slot);
}

void AnsiParser::reset()
{
    m_state = State::Ground;
    m_style = Style();
    m_high = 0;
    m_cr = false;
    m_col = 0;
    m_lastNewline = -1;
    m_csi.clear();
    m_csiPrivate = false;
    m_stringUnits = 0;
    m_escInter = 0;
}

void AnsiParser::feed(QStringView chunk, Parsed &out)
{
    m_lastNewline = out.text.lastIndexOf(QLatin1Char('\n'));
    for (const QChar ch : chunk) {
        step(ch.unicode(), out);
    }
}

void AnsiParser::startCsi()
{
    m_state = State::Csi;
    m_csi.clear();
    m_csiPrivate = false;
    m_escInter = 0;
}

void AnsiParser::startString(bool osc)
{
    m_state = State::String;
    m_stringOsc = osc;
    m_stringUnits = 0;
}

void AnsiParser::step(char16_t c, Parsed &out)
{
    switch (m_state) {
    case State::Ground:
        ground(c, out);
        return;
    case State::Esc:
        if (c == '[') {
            startCsi();
        } else if (c == ']') {
            startString(true);
        } else if (c == 'P' || c == '_' || c == '^' || c == 'X') {
            startString(false);
        } else if (c == 0x1B) {
            // ESC ESC: the second one starts again
        } else if (c >= 0x20 && c <= 0x2F) {
            m_state = State::EscInter;
            m_escInter = 1;
        } else if (c >= 0x30 && c <= 0x7E) {
            m_state = State::Ground; // a two-character escape: dropped
        } else {
            m_state = State::Ground; // a control or a character: the ESC was nothing
            ground(c, out);
        }
        return;
    case State::EscInter:
        if (c >= 0x20 && c <= 0x2F) {
            if (++m_escInter > MaxCsiBytes) {
                m_state = State::Ground;
            }
        } else if (c >= 0x30 && c <= 0x7E) {
            m_state = State::Ground;
        } else {
            m_state = State::Ground;
            ground(c, out);
        }
        return;
    case State::Csi:
        if ((c >= '0' && c <= '9') || c == ';' || c == ':') {
            if (m_csi.size() + m_escInter >= MaxCsiBytes) {
                m_state = State::CsiIgnore;
            } else {
                m_csi.append(char(c));
            }
        } else if (c >= 0x3C && c <= 0x3F) {
            if (m_csi.isEmpty() && !m_csiPrivate) {
                m_csiPrivate = true;
            } else {
                m_state = State::CsiIgnore;
            }
        } else if (c >= 0x20 && c <= 0x2F) {
            m_state = State::CsiInter;
            m_escInter = 1;
        } else if (c >= 0x40 && c <= 0x7E) {
            m_state = State::Ground;
            if (c == 'm' && !m_csiPrivate) {
                sgr();
            }
        } else {
            m_state = State::Ground;
            ground(c, out);
        }
        return;
    case State::CsiInter:
        if (c >= 0x20 && c <= 0x2F) {
            if (m_csi.size() + ++m_escInter > MaxCsiBytes) {
                m_state = State::CsiIgnore;
            }
        } else if (c >= 0x30 && c <= 0x3F) {
            m_state = State::CsiIgnore;
        } else if (c >= 0x40 && c <= 0x7E) {
            m_state = State::Ground;
        } else {
            m_state = State::Ground;
            ground(c, out);
        }
        return;
    case State::CsiIgnore:
        if (c >= 0x20 && c <= 0x3F) {
            // eaten
        } else if (c >= 0x40 && c <= 0x7E) {
            m_state = State::Ground;
        } else {
            m_state = State::Ground;
            ground(c, out);
        }
        return;
    case State::String:
        if (c == 0x1B) {
            m_state = State::StringEsc;
        } else if ((m_stringOsc && c == 0x07) || c == 0x9C || c == 0x18 || c == 0x1A) {
            m_state = State::Ground;
        } else if (++m_stringUnits >= MaxStringUnits) {
            m_state = State::Ground; // never ended: given up, what came is gone
        }
        return;
    case State::StringEsc:
        if (c == '\\') {
            m_state = State::Ground;
        } else {
            m_state = State::Esc;
            step(c, out);
        }
        return;
    }
}

void AnsiParser::ground(char16_t c, Parsed &out)
{
    if (c >= 0xDC00 && c <= 0xDFFF) {
        if (m_high) {
            const char16_t pair[2] = {m_high, c};
            m_high = 0;
            put(pair, 2, out);
        } else {
            put(&Replacement, 1, out);
        }
        return;
    }
    if (m_high) {
        m_high = 0;
        put(&Replacement, 1, out);
    }
    if (c >= 0xD800 && c <= 0xDBFF) {
        m_high = c;
        return;
    }
    if (c < 0x20 || c == 0x7F) {
        switch (c) {
        case 0x1B:
            m_state = State::Esc;
            break;
        case '\n':
            newline(out);
            break;
        case '\r':
            m_cr = true;
            break;
        case '\t':
            put(&c, 1, out);
            break;
        default:
            break; // BEL, backspace, NUL, DEL, ...: nothing
        }
        return;
    }
    if (c >= 0x80 && c <= 0x9F) {
        switch (c) {
        case 0x9B:
            startCsi();
            break;
        case 0x9D:
            startString(true);
            break;
        case 0x90:
        case 0x98:
        case 0x9E:
        case 0x9F:
            startString(false);
            break;
        default:
            break;
        }
        return;
    }
    if (c == 0x2028 || c == 0x2029) {
        newline(out);
        return;
    }
    if (isBidiOrInvisible(c)) {
        return;
    }
    put(&c, 1, out);
}

void AnsiParser::newline(Parsed &out)
{
    m_cr = false; // a CR LF is one newline
    out.text.append(QLatin1Char('\n'));
    m_lastNewline = out.text.size() - 1;
    m_col = 0;
}

void AnsiParser::clearLine(Parsed &out)
{
    if (m_lastNewline >= 0) {
        out.text.truncate(m_lastNewline + 1);
    } else {
        out.text.clear();
        out.clearsLastLine = true;
    }
    const int size = out.text.size();
    while (!out.runs.isEmpty() && out.runs.last().start >= size) {
        out.runs.removeLast();
    }
    if (!out.runs.isEmpty()) {
        Run &r = out.runs.last();
        r.length = std::min(r.length, size - r.start);
    }
    m_col = 0;
}

void AnsiParser::put(const char16_t *units, int count, Parsed &out)
{
    if (m_cr) {
        m_cr = false;
        clearLine(out);
    }
    if (m_col + count > MaxLineUnits) {
        newline(out);
    }
    const int start = out.text.size();
    out.text.append(reinterpret_cast<const QChar *>(units), count);
    m_col += count;
    if (!m_style.isDefault()) {
        if (!out.runs.isEmpty() && out.runs.last().start + out.runs.last().length == start
            && out.runs.last().style == m_style) {
            out.runs.last().length += count;
        } else {
            out.runs.append(Run{start, count, m_style});
        }
    }
}

void AnsiParser::sgr()
{
    Group groups[MaxSgrParams];
    int ng = 0;
    {
        Group cur;
        int value = -1;
        bool open = false; // digits seen for the current number
        auto endNumber = [&] {
            if (cur.n < 8) {
                cur.v[cur.n++] = value;
            }
            value = -1;
            open = false;
        };
        auto endGroup = [&] {
            endNumber();
            if (ng < MaxSgrParams) {
                groups[ng++] = cur;
            }
            cur = Group();
        };
        for (const char b : std::as_const(m_csi)) {
            if (b >= '0' && b <= '9') {
                if (value != -2) {
                    value = (open ? value : 0) * 10 + (b - '0');
                    if (value > 65535) {
                        value = -2;
                    }
                }
                open = true;
            } else if (b == ':') {
                endNumber();
            } else { // ';'
                endGroup();
            }
        }
        endGroup();
    }

    Style &s = m_style;
    auto setColor = [&](bool fg, int mode, const int *a, int n) {
        // mode 5: a[0] is the index; mode 2: a[0..2] are r, g, b.
        auto val = [](int v) { return v == -1 ? 0 : v; };
        quint8 slot;
        if (mode == 5 && n >= 1 && val(a[0]) >= 0 && val(a[0]) <= 255) {
            slot = slotFor256(val(a[0]));
        } else if (mode == 2 && n >= 3 && val(a[0]) >= 0 && val(a[0]) <= 255 && val(a[1]) >= 0
                   && val(a[1]) <= 255 && val(a[2]) >= 0 && val(a[2]) <= 255) {
            slot = slotForRgb(val(a[0]), val(a[1]), val(a[2]));
        } else {
            return;
        }
        (fg ? s.fg : s.bg) = slot;
    };

    for (int i = 0; i < ng; ++i) {
        const Group &g = groups[i];
        int code = g.v[0];
        if (code == -2) {
            continue;
        }
        if (code == -1) {
            code = 0;
        }
        if (g.n > 1) {
            // Colon form: 38:5:n, 38:2:r:g:b, 38:2::r:g:b, 4:3, ...
            if (code == 38 || code == 48) {
                const int mode = g.v[1];
                if (mode == 5) {
                    setColor(code == 38, 5, g.v + 2, g.n - 2);
                } else if (mode == 2) {
                    // an optional colour-space number before r, g, b
                    const int skip = g.n - 2 >= 4 ? 1 : 0;
                    setColor(code == 38, 2, g.v + 2 + skip, g.n - 2 - skip);
                }
                continue;
            }
            if (code == 58) {
                continue;
            }
            if (code == 4) {
                if (g.v[1] == 0) {
                    s.flags &= ~Underline;
                } else {
                    s.flags |= Underline;
                }
                continue;
            }
        } else if (code == 38 || code == 48 || code == 58) {
            // Semicolon form: the next groups hold the mode and the numbers.
            if (i + 1 >= ng) {
                break;
            }
            const int mode = groups[i + 1].v[0];
            if (mode == 5) {
                if (i + 2 >= ng) {
                    break;
                }
                const int a[1] = {groups[i + 2].v[0]};
                if (code != 58) {
                    setColor(code == 38, 5, a, 1);
                }
                i += 2;
            } else if (mode == 2) {
                if (i + 4 >= ng) {
                    break;
                }
                const int a[3] = {groups[i + 2].v[0], groups[i + 3].v[0], groups[i + 4].v[0]};
                if (code != 58) {
                    setColor(code == 38, 2, a, 3);
                }
                i += 4;
            } else {
                i += 1;
            }
            continue;
        }
        switch (code) {
        case 0:
            s = Style();
            break;
        case 1:
            s.flags |= Bold;
            break;
        case 2:
            s.flags |= Dim;
            break;
        case 3:
            s.flags |= Italic;
            break;
        case 4:
            s.flags |= Underline;
            break;
        case 7:
            s.flags |= Inverse;
            break;
        case 9:
            s.flags |= Strike;
            break;
        case 22:
            s.flags &= ~(Bold | Dim);
            break;
        case 23:
            s.flags &= ~Italic;
            break;
        case 24:
            s.flags &= ~Underline;
            break;
        case 27:
            s.flags &= ~Inverse;
            break;
        case 29:
            s.flags &= ~Strike;
            break;
        case 39:
            s.fg = NoColor;
            break;
        case 49:
            s.bg = NoColor;
            break;
        default:
            if (code >= 30 && code <= 37) {
                s.fg = quint8(code - 30);
            } else if (code >= 40 && code <= 47) {
                s.bg = quint8(code - 40);
            } else if (code >= 90 && code <= 97) {
                s.fg = quint8(code - 90 + 8);
            } else if (code >= 100 && code <= 107) {
                s.bg = quint8(code - 100 + 8);
            }
            break; // anything else is ignored
        }
    }
}

} // namespace TelamonConsole
