// The ANSI parser behind TelamonConsoleView (ui/console/ansiparser.cpp, compiled
// into this test) and the colours that make of its palette slots
// (ui/console/consoletheme.cpp): every SGR feature, the colour approximation,
// every kind of escape sequence that must vanish, hostile input, and a fuzz test
// of the invariants. See tests/README.md.
#include "ansiparser.h"
#include "consoletheme.h"

#include <QElapsedTimer>
#include <QGuiApplication>
#include <QRandomGenerator>
#include <QtTest>

using namespace TelamonConsole;

namespace {

// What a view holds after the parser's output went in: the lines and the runs
// of each. Written apart from the sink on purpose.
struct Model
{
    QStringList lines{QString()};
    QList<QList<Run>> runs{{}};

    void apply(const Parsed &p)
    {
        if (p.clearsLastLine) {
            lines.last().clear();
            runs.last().clear();
        }
        int line = lines.size() - 1;
        int col = lines.last().size();
        QList<int> lineOf;
        QList<int> colOf;
        for (const QChar c : p.text) {
            lineOf.append(line);
            colOf.append(col);
            if (c == QLatin1Char('\n')) {
                ++line;
                col = 0;
                lines.append(QString());
                runs.append(QList<Run>());
            } else {
                lines[line].append(c);
                ++col;
            }
        }
        for (const Run &r : p.runs) {
            const int l = lineOf.at(r.start);
            Run placed = r;
            placed.start = colOf.at(r.start);
            QList<Run> &target = runs[l];
            if (!target.isEmpty() && target.last().start + target.last().length == placed.start && target.last().style == placed.style) {
                target.last().length += placed.length;
            } else {
                target.append(placed);
            }
        }
    }
    QString text() const { return lines.join(QLatin1Char('\n')); }
    bool operator==(const Model &o) const
    {
        if (lines != o.lines || runs.size() != o.runs.size()) {
            return false;
        }
        for (int i = 0; i < runs.size(); ++i) {
            if (runs[i].size() != o.runs[i].size()) {
                return false;
            }
            for (int j = 0; j < runs[i].size(); ++j) {
                const Run &a = runs[i][j];
                const Run &b = o.runs[i][j];
                if (a.start != b.start || a.length != b.length || a.style != b.style) {
                    return false;
                }
            }
        }
        return true;
    }
};

Model parseWhole(const QString &s)
{
    AnsiParser parser;
    Model m;
    Parsed p;
    parser.feed(s, p);
    m.apply(p);
    return m;
}

Model parseChunks(const QString &s, const QList<int> &sizes)
{
    AnsiParser parser;
    Model m;
    int pos = 0;
    int i = 0;
    while (pos < s.size()) {
        const int n = std::min<int>(sizes.at(i++ % sizes.size()), s.size() - pos);
        Parsed p;
        parser.feed(QStringView(s).mid(pos, n), p);
        m.apply(p);
        pos += n;
    }
    return m;
}

Model parseUnits(const QString &s)
{
    return parseChunks(s, {1});
}

// A '^' stands for ESC in the tables below: easier to read.
QString esc(const char *s)
{
    return QString::fromUtf8(s).replace(QLatin1Char('^'), QChar(0x1B));
}

QString U(char16_t c)
{
    return QString(QChar(c));
}

// The style of the "X" that ends `seq`.
Style styleOfX(const QString &seq)
{
    const Model m = parseWhole(esc(seq.toUtf8().constData()) + QLatin1Char('X'));
    if (m.text() != QLatin1String("X")) {
        return Style{0, 0, 0xFF};
    }
    return m.runs.first().isEmpty() ? Style() : m.runs.first().first().style;
}

bool bad(char16_t c)
{
    return c == 0x1B || (c < 0x20 && c != '\n' && c != '\t') || (c >= 0x7F && c <= 0x9F) || c == 0x2028 || c == 0x2029
        || c == 0x061C || (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069)
        || c == 0xFEFF;
}

// Valid UTF-16: every surrogate in a pair.
bool wellFormed(const QString &s)
{
    for (int i = 0; i < s.size(); ++i) {
        const QChar c = s.at(i);
        if (c.isHighSurrogate()) {
            if (i + 1 >= s.size() || !s.at(i + 1).isLowSurrogate()) {
                return false;
            }
            ++i;
        } else if (c.isLowSurrogate()) {
            return false;
        }
    }
    return true;
}

} // namespace

class TestAnsiParser : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void plainText()
    {
        const Model m = parseWhole(QStringLiteral("hello\nworld\ttab"));
        QCOMPARE(m.lines, (QStringList{QStringLiteral("hello"), QStringLiteral("world\ttab")}));
        QVERIFY(m.runs[0].isEmpty() && m.runs[1].isEmpty());
    }

    void sgrRuns()
    {
        const Model m = parseWhole(esc("a^[31mred^[0m plain^[1;4mbu^[m"));
        QCOMPARE(m.text(), QStringLiteral("ared plainbu"));
        QCOMPARE(m.runs[0].size(), 2);
        QCOMPARE(m.runs[0][0].start, 1);
        QCOMPARE(m.runs[0][0].length, 3);
        QCOMPARE(int(m.runs[0][0].style.fg), 1);
        QCOMPARE(m.runs[0][1].start, 10);
        QCOMPARE(m.runs[0][1].length, 2);
        QCOMPARE(int(m.runs[0][1].style.flags), int(Bold | Underline));
    }

    void sgrPersistsAcrossLinesAndChunks()
    {
        const Model m = parseWhole(esc("^[32mone\ntwo\n^[0mthree"));
        QCOMPARE(m.lines, (QStringList{QStringLiteral("one"), QStringLiteral("two"), QStringLiteral("three")}));
        QCOMPARE(m.runs[0].size(), 1);
        QCOMPARE(m.runs[1].size(), 1);
        QCOMPARE(m.runs[1][0].length, 3);
        QVERIFY(m.runs[2].isEmpty());
        // a run never holds a newline, and the parser keeps its state between calls
        AnsiParser p;
        Parsed a;
        p.feed(QString(esc("^[1;31m")), a);
        QCOMPARE(int(p.style().flags), int(Bold));
        p.reset();
        QVERIFY(p.style().isDefault());
    }

    void sgrFeatures_data()
    {
        QTest::addColumn<QString>("seq");
        QTest::addColumn<int>("fg");
        QTest::addColumn<int>("bg");
        QTest::addColumn<int>("flags");
        const int N = NoColor;
        QTest::newRow("bold") << "^[1m" << N << N << int(Bold);
        QTest::newRow("dim") << "^[2m" << N << N << int(Dim);
        QTest::newRow("italic") << "^[3m" << N << N << int(Italic);
        QTest::newRow("underline") << "^[4m" << N << N << int(Underline);
        QTest::newRow("inverse") << "^[7m" << N << N << int(Inverse);
        QTest::newRow("strike") << "^[9m" << N << N << int(Strike);
        QTest::newRow("reset 0") << "^[1;31;42m^[0m" << N << N << 0;
        QTest::newRow("reset empty") << "^[1;31m^[m" << N << N << 0;
        QTest::newRow("reset empty params") << "^[1;31m^[;m" << N << N << 0;
        QTest::newRow("22 bold and dim off") << "^[1;2;3m^[22m" << N << N << int(Italic);
        QTest::newRow("23") << "^[3;4m^[23m" << N << N << int(Underline);
        QTest::newRow("24") << "^[3;4m^[24m" << N << N << int(Italic);
        QTest::newRow("27") << "^[7;1m^[27m" << N << N << int(Bold);
        QTest::newRow("29") << "^[9;1m^[29m" << N << N << int(Bold);
        for (int i = 0; i < 8; ++i) {
            QTest::addRow("fg %d", 30 + i) << QStringLiteral("^[%1m").arg(30 + i) << i << N << 0;
            QTest::addRow("bg %d", 40 + i) << QStringLiteral("^[%1m").arg(40 + i) << N << i << 0;
            QTest::addRow("bright fg %d", 90 + i) << QStringLiteral("^[%1m").arg(90 + i) << 8 + i << N << 0;
            QTest::addRow("bright bg %d", 100 + i) << QStringLiteral("^[%1m").arg(100 + i) << N << 8 + i << 0;
        }
        QTest::newRow("39") << "^[31;42m^[39m" << N << 2 << 0;
        QTest::newRow("49") << "^[31;42m^[49m" << 1 << N << 0;
        QTest::newRow("256 basic") << "^[38;5;9m" << 9 << N << 0;
        QTest::newRow("256 bg") << "^[48;5;4m" << N << 4 << 0;
        QTest::newRow("256 cube red") << "^[38;5;196m" << 9 << N << 0;
        QTest::newRow("256 grey") << "^[38;5;244m" << 16 + 4 << N << 0;
        QTest::newRow("truecolour") << "^[38;2;255;0;0m" << 9 << N << 0;
        QTest::newRow("truecolour bg") << "^[48;2;0;128;0m" << N << 2 << 0;
        QTest::newRow("colon 256") << "^[38:5:12m" << 12 << N << 0;
        QTest::newRow("colon truecolour") << "^[38:2:0:0:255m" << 12 << N << 0;
        QTest::newRow("colon truecolour with colour space") << "^[48:2::0:255:0m" << N << 10 << 0;
        QTest::newRow("colon underline style") << "^[4:3m" << N << N << int(Underline);
        QTest::newRow("colon underline off") << "^[4m^[4:0m" << N << N << 0;
        QTest::newRow("unknown numbers are ignored") << "^[5;8;21;53;1m" << N << N << int(Bold);
        QTest::newRow("underline colour is skipped") << "^[58;2;1;2;3;1m" << N << N << int(Bold);
        QTest::newRow("underline colour 256 is skipped") << "^[58;5;9;3m" << N << N << int(Italic);
        QTest::newRow("combined") << "^[1;3;38;5;2;48;5;1m" << 2 << 1 << int(Bold | Italic);
        QTest::newRow("incomplete 38") << "^[1;38;5m" << N << N << int(Bold);
        QTest::newRow("incomplete truecolour") << "^[1;38;2;1;2m" << N << N << int(Bold);
        QTest::newRow("index too big") << "^[38;5;256;1m" << N << N << int(Bold);
        QTest::newRow("rgb too big") << "^[38;2;300;0;0;1m" << N << N << int(Bold);
        QTest::newRow("huge number") << "^[99999999999999999999;1m" << N << N << int(Bold);
        QTest::newRow("huge colour index") << "^[38;5;99999999999m" << N << N << 0;
        QTest::newRow("unknown 38 mode") << "^[38;9;1m" << N << N << int(Bold);
        QTest::newRow("last of many") << "^[1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;1;31m" << 1 << N << int(Bold);
        QTest::newRow("beyond 32 params is ignored") << "^[0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;0;1m" << N << N << 0;
    }
    void sgrFeatures()
    {
        QFETCH(QString, seq);
        QFETCH(int, fg);
        QFETCH(int, bg);
        QFETCH(int, flags);
        const Style s = styleOfX(seq);
        QCOMPARE(int(s.fg), fg);
        QCOMPARE(int(s.bg), bg);
        QCOMPARE(int(s.flags), flags);
    }

    void colourApproximation()
    {
        for (int i = 0; i < 16; ++i) {
            QCOMPARE(int(slotFor256(i)), i);
        }
        QCOMPARE(int(slotFor256(196)), 9);   // 255,0,0: bright red
        QCOMPARE(int(slotFor256(160)), 1);   // 215,0,0: red
        QCOMPARE(int(slotFor256(46)), 10);   // bright green
        QCOMPARE(int(slotFor256(34)), 2);    // 0,175,0: green
        QCOMPARE(int(slotFor256(21)), 12);   // bright blue
        QCOMPARE(int(slotFor256(226)), 11);  // bright yellow
        QCOMPARE(int(slotFor256(51)), 14);   // bright cyan
        QCOMPARE(int(slotFor256(201)), 13);  // bright magenta
        QCOMPARE(int(slotFor256(17)), 4);    // 0,0,95: blue
        QCOMPARE(int(slotFor256(16)), 16);   // black is the muted end of the ramp
        QCOMPARE(int(slotFor256(231)), 23);  // white is the text end
        QCOMPARE(int(slotFor256(232)), 16);
        QCOMPARE(int(slotFor256(255)), 23);
        QCOMPARE(int(slotFor256(-1)), int(NoColor));
        QCOMPARE(int(slotFor256(256)), int(NoColor));
        // greys by lightness, increasing
        int last = 0;
        for (int v = 0; v <= 255; v += 5) {
            const int s = slotForRgb(v, v, v);
            QVERIFY(s >= 16 && s <= 23);
            QVERIFY(s >= last);
            last = s;
        }
        // low saturation is grey, however it leans
        QVERIFY(slotForRgb(120, 128, 135) >= 16);
        QVERIFY(slotForRgb(30, 10, 10) >= 16);
        // the six hues
        QCOMPARE(int(slotForRgb(200, 0, 0)), 1);
        QCOMPARE(int(slotForRgb(0, 200, 0)), 2);
        QCOMPARE(int(slotForRgb(200, 200, 0)), 3);
        QCOMPARE(int(slotForRgb(0, 0, 200)), 4);
        QCOMPARE(int(slotForRgb(200, 0, 200)), 5);
        QCOMPARE(int(slotForRgb(0, 200, 200)), 6);
        QCOMPARE(int(slotForRgb(255, 128, 128)), 9);
        QCOMPARE(int(slotForRgb(255, 140, 0)), 11); // orange: nearer yellow than red? 33 degrees
        // out of range input is clamped
        QVERIFY(slotForRgb(-5, 999, 0) < PaletteSlots);
    }

    void chunkSplitsEqualOneShot_data()
    {
        QTest::addColumn<QString>("input");
        const char *rows[] = {
            "a^[31mred^[0mb",
            "^[1;38;5;196mx^[0m",
            "^[38;2;1;2;3mtruecolour^[m",
            "^[38:2::10:20:30mcolon^[m",
            "one\r\ntwo\rthree\r\r\nfour\n",
            "progress 10%\rprogress 20%\rprogress 30%\n",
            "^]8;;https://example.com^\\link^]8;;^\\ text",
            "^]0;title\atext^]2;t2^\\more",
            "^P1$r0m^\\after",
            "^_app^\\after",
            "^[2J^[H^[1000Aafter",
            "^[?1049hscreen^[?1049l",
            "^(B^)0text^c^7^=",
            "x^[31;1H^[K^[6nrest",
            "emoji \xF0\x9F\x98\x80 and \xF0\x9F\x91\x8D\n",
            "bad ^[31\nline ^[1;mgood",
            "ctrl \x07\x08\x0b\x0c\x7f\x01 gone",
            "bidi \xE2\x80\xAE" "txt \xE2\x81\xA6 \xEF\xBB\xBF \xE2\x80\x8B end",
            "ls \xE2\x80\xA8" "sep\xE2\x80\xA9" "end",
        };
        for (const char *r : rows) {
            QTest::newRow(r) << esc(r);
        }
        QTest::newRow("c1") << QStringLiteral("a\x9b" "31mred\x9b" "0m \x9d" "0;t\ab \x90" "x\x9c" "c \x85" "d");
        QTest::newRow("lone surrogates") << QStringLiteral("a") + U(0xD83D) + QStringLiteral("b") + U(0xDE00) + QStringLiteral("c") + U(0xD83D) + U(0xDE00);
    }
    void chunkSplitsEqualOneShot()
    {
        QFETCH(QString, input);
        const Model whole = parseWhole(input);
        QVERIFY(parseUnits(input) == whole);
        QVERIFY(parseChunks(input, {2}) == whole);
        QVERIFY(parseChunks(input, {3, 1, 5}) == whole);
        QVERIFY(parseChunks(input, {7}) == whole);
    }

    void cr_data()
    {
        QTest::addColumn<QStringList>("chunks");
        QTest::addColumn<QStringList>("lines");
        QTest::newRow("crlf") << QStringList{"a\r\nb"} << QStringList{"a", "b"};
        QTest::newRow("crlf split") << QStringList{"a\r", "\nb"} << QStringList{"a", "b"};
        QTest::newRow("lone cr rewrites") << QStringList{"abc\rde"} << QStringList{"de"};
        QTest::newRow("cr rewrites the partial last line") << QStringList{"abc", "\rx"} << QStringList{"x"};
        QTest::newRow("cr only touches the last line") << QStringList{"one\ntwo\rx"} << QStringList{"one", "x"};
        QTest::newRow("cr cr text") << QStringList{"abc\r\rx"} << QStringList{"x"};
        QTest::newRow("cr at the end waits") << QStringList{"abc\r"} << QStringList{"abc"};
        QTest::newRow("cr then newline keeps the line") << QStringList{"abc\r", "", "\n"} << QStringList{"abc", ""};
        QTest::newRow("progress bar") << QStringList{"10%\r20%\r30%\n"} << QStringList{"30%", ""};
        QTest::newRow("cr, control, text") << QStringList{"abc\r\x07\x08xy"} << QStringList{"xy"};
        QTest::newRow("cr tab") << QStringList{"abc\r\tz"} << QStringList{"\tz"};
        QTest::newRow("cr after an escape") << QStringList{"abc\r\x1b[31mxy"} << QStringList{"xy"};
        QTest::newRow("U+2028 and U+2029 are newlines") << QStringList{QStringLiteral("a\u2028b\u2029c")} << QStringList{"a", "b", "c"};
    }
    void cr()
    {
        QFETCH(QStringList, chunks);
        QFETCH(QStringList, lines);
        AnsiParser parser;
        Model m;
        for (const QString &c : chunks) {
            Parsed p;
            parser.feed(c, p);
            m.apply(p);
        }
        QCOMPARE(m.lines, lines);
    }

    void crClearsColoursOfTheLine()
    {
        const Model m = parseWhole(esc("^[31mred\r^[32mgreen"));
        QCOMPARE(m.lines.first(), QStringLiteral("green"));
        QCOMPARE(m.runs.first().size(), 1);
        QCOMPARE(int(m.runs.first()[0].style.fg), 2);
        QCOMPARE(m.runs.first()[0].start, 0);
        QCOMPARE(m.runs.first()[0].length, 5);
    }

    void longLinesSplit()
    {
        const Model m = parseWhole(QString(5000, QLatin1Char('a')) + QStringLiteral("\nb"));
        QCOMPARE(m.lines.size(), 3);
        QCOMPARE(m.lines[0].size(), MaxLineUnits);
        QCOMPARE(m.lines[1].size(), 5000 - MaxLineUnits);
        QCOMPARE(m.lines[2], QStringLiteral("b"));
        // exactly the limit: no extra line
        const Model e = parseWhole(QString(MaxLineUnits, QLatin1Char('a')) + QStringLiteral("\nb"));
        QCOMPARE(e.lines.size(), 2);
        // a surrogate pair is not cut
        const Model s = parseWhole(QString(MaxLineUnits - 1, QLatin1Char('a')) + QStringLiteral("\U0001F600z"));
        QCOMPARE(s.lines.size(), 2);
        QCOMPARE(s.lines[0].size(), MaxLineUnits - 1);
        QVERIFY(wellFormed(s.lines[1]));
        // chunked, and with colours, the same
        const QString coloured = esc("^[31m") + QString(9000, QLatin1Char('x'));
        QVERIFY(parseChunks(coloured, {1000}) == parseWhole(coloured));
        const Model c = parseWhole(coloured);
        QCOMPARE(c.runs[0][0].length, MaxLineUnits);
        QCOMPARE(c.runs[1][0].length, MaxLineUnits);
        QCOMPARE(c.runs[2][0].length, 9000 - 2 * MaxLineUnits);
    }

    void surrogates()
    {
        QCOMPARE(parseWhole(QStringLiteral("a") + U(0xD83D) + QStringLiteral("b")).text(), QStringLiteral("a\ufffd" "b"));
        QCOMPARE(parseWhole(QStringLiteral("a") + U(0xDE00) + QStringLiteral("b")).text(), QStringLiteral("a\ufffd" "b"));
        QCOMPARE(parseWhole(U(0xD83D) + U(0xD83D) + U(0xDE00)).text(), QStringLiteral("\ufffd\U0001F600"));
        QCOMPARE(parseWhole(QStringLiteral("a\U0001F600b")).text(), QStringLiteral("a\U0001F600b"));
        // a pair split across two calls
        AnsiParser p;
        Parsed a;
        const QString first = QStringLiteral("a") + U(0xD83D);
        p.feed(first, a);
        QCOMPARE(a.text, QStringLiteral("a"));
        Parsed b;
        const QString second = U(0xDE00) + QStringLiteral("z");
        p.feed(second, b);
        QCOMPARE(b.text, QStringLiteral("\U0001F600z"));
        // a lone high surrogate before an escape or a newline
        QCOMPARE(parseWhole(U(0xD83D) + esc("^[31mx")).text(), QStringLiteral("\ufffdx"));
        QCOMPARE(parseWhole(U(0xD83D) + QStringLiteral("\n")).text(), QStringLiteral("\ufffd\n"));
    }

    // Every kind of sequence that must leave no trace but the text around it.
    void stripped_data()
    {
        QTest::addColumn<QString>("input");
        QTest::addColumn<QString>("shown");
        auto row = [](const char *name, const QString &in, const QString &out) { QTest::newRow(name) << in << out; };
        row("csi erase", esc("a^[2Jb"), "ab");
        row("csi home", esc("a^[Hb"), "ab");
        row("csi cursor up 1000", esc("a^[1000Ab"), "ab");
        row("csi cursor position", esc("a^[10;20Hb"), "ab");
        row("csi erase line", esc("a^[Kb^[2Kc"), "abc");
        row("csi scroll region", esc("a^[1;24rb"), "ab");
        row("csi private mode set", esc("a^[?1049hb^[?25lc^[?25hd"), "abcd");
        row("csi device report", esc("a^[6nb^[0cc"), "abc");
        row("csi private marker m is not a colour", esc("a^[>4;2mb^[?1mc"), "abc");
        row("csi with intermediate", esc("a^[0 qb^[1$pc^[!pd"), "abcd");
        row("csi final other than m with colour numbers", esc("a^[31Hb^[1;31fc"), "abc");
        row("malformed csi ended by newline", esc("a^[31\nb"), "a\nb");
        row("malformed csi ended by tab", esc("a^[3\tb"), "a\tb");
        row("malformed csi ended by esc", esc("a^[31^[32mb"), "ab");
        row("malformed csi ended by non-ascii", esc("a^[31\u00e9b"), "a\u00e9b");
        row("marker in the middle", esc("a^[1?2mb"), "ab");
        row("parameter after intermediate", esc("a^[1 1mb"), "ab");
        row("osc title with bel", esc("a^]0;my title\ab"), "ab");
        row("osc title with st", esc("a^]2;my title^\\b"), "ab");
        row("osc 8 hyperlink", esc("a^]8;;https://evil.example/x^\\link^]8;;^\\b"), "alinkb");
        row("osc 52 clipboard", esc("a^]52;c;aGVsbG8=\ab"), "ab");
        row("osc ended by c1 st", QStringLiteral("a\x1b]0;t\x9c" "" "b"), "ab");
        row("osc cancelled by can", QStringLiteral("a\x1b]0;t\x18" "b"), "ab");
        row("dcs", esc("a^P1$qm^\\b"), "ab");
        row("dcs with embedded esc starts a new sequence", esc("a^P1$q^[31mx^\\b"), "axb");
        row("apc", esc("a^_Gi=1;data^\\b"), "ab");
        row("pm", QStringLiteral("a\x1b^private\x1b\\b"), "ab");
        row("sos", esc("a^Xstring^\\b"), "ab");
        row("dcs is not ended by bel", esc("a^Pq\ab^\\c"), "ac");
        row("charset selection", esc("a^(Bb^)0c^*Ad^+1e"), "abcde");
        row("two-character escapes", esc("a^cb^7c^8d^=e^>f^Mg^Dh^Ei^Hj"), "abcdefghij");
        row("stray st", esc("a^\\b"), "ab");
        row("esc followed by control", esc("a^\nb"), "a\nb");
        row("esc esc", esc("a^^[31mb"), "ab");
        row("c1 csi", QStringLiteral("a\x9b" "31mb"), "ab");
        row("c1 csi erase", QStringLiteral("a\x9b" "2Jb"), "ab");
        row("c1 osc", QStringLiteral("a\x9d" "0;title\a" "b"), "ab");
        row("c1 dcs apc pm sos", QStringLiteral("a\x90" "q\x9c" "" "b\x9f" "x\x9c" "" "c\x9e" "y\x9c" "" "d\x98" "z\x9c" "" "e"), "abcde");
        row("other c1 are dropped", QStringLiteral("a\x80" "\x85" "\x89" "\x99" "\x9a" "\x9c" "" "b"), "ab");
        row("bel storm", QString(10000, QChar(7)) + QStringLiteral("a"), "a");
        row("backspace", QStringLiteral("ab\b\b\bc"), "abc");
        row("nul, vt, ff, del, so, si", QString(QStringLiteral("a\0b\vc\fd\x7f" "e\x0e" "f\x0f" "g")), "abcdefg");
        row("bidi override", QStringLiteral("a\u202e" "b\u202c" "c\u2066" "d\u2069" "e\u200e\u200f\u061c" "f\ufeff\u200b\u200c\u200d" "g"), "abcdefg");
        row("html stays text", QStringLiteral("<b>x</b> &amp; <a href=\"x\">l</a> **md**"), "<b>x</b> &amp; <a href=\"x\">l</a> **md**");
        row("esc at the very end", esc("abc^"), "abc");
        row("csi at the very end", esc("abc^[31"), "abc");
        row("osc at the very end", esc("abc^]0;never ended"), "abc");
    }
    void stripped()
    {
        QFETCH(QString, input);
        QFETCH(QString, shown);
        QCOMPARE(parseWhole(input).text(), shown);
        QCOMPARE(parseUnits(input).text(), shown);
    }

    void unterminatedOscIsBounded()
    {
        // Never ended: the 4096 units that were swallowed are gone, then text goes on.
        const QString input = esc("^]0;") + QString(5000, QLatin1Char('x')) + QStringLiteral("tail");
        const Model m = parseWhole(input);
        QVERIFY(m.text().endsWith(QStringLiteral("tail")));
        QCOMPARE(int(m.text().size()), 5000 + 4 + 2 - MaxStringUnits);
        QVERIFY(parseUnits(input) == m);
        // the same for a DCS
        const Model d = parseWhole(esc("^P") + QString(5000, QLatin1Char('x')) + QStringLiteral("tail"));
        QVERIFY(d.text().endsWith(QStringLiteral("tail")));
        QVERIFY(d.text().size() < 1100);
        // a string that ends in time is gone whole
        QCOMPARE(parseWhole(esc("^]0;") + QString(4000, QLatin1Char('x')) + esc("\aok")).text(), QStringLiteral("ok"));
    }

    void csiLimits()
    {
        // 10000 parameters: the whole sequence is dropped and nothing of it shows.
        QString many = esc("^[");
        for (int i = 0; i < 10000; ++i) {
            many += QStringLiteral("1;");
        }
        many += QStringLiteral("mX");
        const Model m = parseWhole(many);
        QCOMPARE(m.text(), QStringLiteral("X"));
        QVERIFY(m.runs[0].isEmpty());
        QVERIFY(parseUnits(many) == m);
        // 64 parameter bytes are fine, 65 are not
        QString ok = esc("^[") + QString(31, QLatin1Char('0')) + QStringLiteral(";1mX");
        QCOMPARE(int(styleOfX(QString(ok).remove('X')).flags), int(Bold));
        QString tooLong = esc("^[") + QString(70, QLatin1Char('0')) + QStringLiteral(";1mX");
        QVERIFY(parseWhole(tooLong).runs[0].isEmpty());
        // a huge number
        QVERIFY(parseWhole(esc("^[99999999999999999999mX")).runs[0].isEmpty());
        QCOMPARE(parseWhole(esc("^[99999999999999999999mX")).text(), QStringLiteral("X"));
        // too many intermediates
        QCOMPARE(parseWhole(esc("^[") + QString(500, QLatin1Char(' ')) + QStringLiteral("qX")).text(), QStringLiteral("X"));
    }

    void escSplitBetweenCalls()
    {
        AnsiParser p;
        Model m;
        for (const QString &chunk : {esc("a^["), QStringLiteral("3"), QStringLiteral("1"), esc("mb^"), esc("]0;t^"), QStringLiteral("\\c")}) {
            Parsed out;
            p.feed(chunk, out);
            m.apply(out);
        }
        QCOMPARE(m.text(), QStringLiteral("abc"));
        QCOMPARE(m.runs[0].size(), 1);
        QCOMPARE(m.runs[0][0].start, 1);
        QCOMPARE(m.runs[0][0].length, 2);
    }

    void resetForgetsEverything()
    {
        AnsiParser p;
        Parsed a;
        p.feed(esc("^[1;31mabc\r^[3"), a);
        p.reset();
        Parsed b;
        p.feed(QStringLiteral("1mx"), b);
        QCOMPARE(b.text, QStringLiteral("1mx"));
        QVERIFY(b.runs.isEmpty());
        QVERIFY(!b.clearsLastLine);
    }

    // Random hostile text in random chunks: the invariants hold, nothing hangs.
    void fuzz()
    {
        const QString alphabet[] = {
            QStringLiteral("\x1b"), QStringLiteral("["), QStringLiteral("]"), QStringLiteral(";"), QStringLiteral(":"),
            QStringLiteral("0"), QStringLiteral("1"), QStringLiteral("3"), QStringLiteral("8"), QStringLiteral("5"),
            QStringLiteral("2"), QStringLiteral("9"), QStringLiteral("m"), QStringLiteral("H"), QStringLiteral("\x07"),
            QStringLiteral("\r"), QStringLiteral("\n"), QStringLiteral("\t"), QStringLiteral("\x9b" ""), QStringLiteral("\x9d" ""),
            QStringLiteral("\x90" ""), QStringLiteral("\x9c" ""), QStringLiteral("\x85" ""), QStringLiteral("a"), QStringLiteral("Z"),
            QStringLiteral(" "), QStringLiteral("\u00e9"), QStringLiteral("\\"), QStringLiteral("P"), QStringLiteral("_"),
            QStringLiteral("?"), QStringLiteral("("), U(0xD83D), U(0xDE00),
            QStringLiteral("\U0001F600"), QStringLiteral("\u202e"), QStringLiteral("\u2066"), QStringLiteral("\u200b"),
            QStringLiteral("\ufeff"), QStringLiteral("\u2028"), QStringLiteral("\x7f"), QStringLiteral("\x08"),
            QStringLiteral("\x18"), QString(QChar(0)), QStringLiteral("9999999999"),
        };
        const int n = sizeof(alphabet) / sizeof(alphabet[0]);
        QRandomGenerator rng(20260511);
        QElapsedTimer timer;
        timer.start();
        qint64 worst = 0;
        for (int iteration = 0; iteration < 20000; ++iteration) {
            QString input;
            const int pieces = rng.bounded(0, iteration % 50 == 0 ? 3000 : 120);
            for (int i = 0; i < pieces; ++i) {
                input += alphabet[rng.bounded(n)];
            }
            QList<int> sizes;
            for (int i = 0; i < 6; ++i) {
                sizes.append(rng.bounded(1, 40));
            }
            const qint64 t0 = timer.nsecsElapsed();
            const Model whole = parseWhole(input);
            const Model chunked = parseChunks(input, sizes);
            worst = std::max(worst, timer.nsecsElapsed() - t0);

            const QString shown = whole.text();
            QVERIFY2(shown.size() <= input.size(), qPrintable(QString::number(iteration)));
            for (const QChar c : shown) {
                QVERIFY2(!bad(c.unicode()), qPrintable(QStringLiteral("iteration %1: U+%2").arg(iteration).arg(int(c.unicode()), 4, 16)));
            }
            QVERIFY2(wellFormed(shown), qPrintable(QString::number(iteration)));
            QVERIFY2(whole == chunked, qPrintable(QStringLiteral("iteration %1: chunks differ").arg(iteration)));
            for (int l = 0; l < whole.lines.size(); ++l) {
                int end = 0;
                for (const Run &r : whole.runs[l]) {
                    QVERIFY(r.length > 0);
                    QVERIFY(r.start >= end);
                    QVERIFY(r.start + r.length <= whole.lines[l].size());
                    QVERIFY(!r.style.isDefault());
                    QVERIFY(r.style.fg == NoColor || r.style.fg < PaletteSlots);
                    QVERIFY(r.style.bg == NoColor || r.style.bg < PaletteSlots);
                    QVERIFY(!(r.style.flags & ~0x3F));
                    end = r.start + r.length;
                }
            }
        }
        QVERIFY2(timer.elapsed() < 30000, "the fuzz test took too long");
        qInfo() << "fuzz: 20000 strings in" << timer.elapsed() << "ms, slowest one" << worst / 1000 << "us";
    }

    void largeInputIsFast()
    {
        QString big;
        for (int i = 0; i < 100000; ++i) {
            big += QStringLiteral("\x1b[32mline ") + QString::number(i) + QStringLiteral("\x1b[0m done\n");
        }
        QElapsedTimer t;
        t.start();
        AnsiParser p;
        Parsed out;
        p.feed(big, out);
        qInfo() << "parse of" << big.size() / 1024 << "KiB with 200000 colour sequences:" << t.elapsed() << "ms";
        QCOMPARE(out.runs.size(), 100000);
        QVERIFY(t.elapsed() < 3000);
    }
};

class TestConsoleTheme : public QObject
{
    Q_OBJECT

    static QList<QColor> sample(bool dark)
    {
        // The Breeze-like colours TelamonStyle gives, light and dark.
        if (dark) {
            return {QColor(255, 255, 255, 166), QColor("#FF959E"), QColor("#74DE9C"), QColor("#FFBB63"), QColor("#3DAEE9"),
                    QColor("#A396F7"), QColor("#5CC6C0"), QColor("#FCFCFC"), QColor("#FFD0D4"), QColor("#B8F0CB"),
                    QColor("#FFE0B3"), QColor("#9CD7F4"), QColor("#C9C2FB"), QColor("#B6E3E0"), QColor("#FFFFFF"), QColor("#FFFFFF")};
        }
        return {QColor(35, 38, 39, 166), QColor("#AB1E2C"), QColor("#14602F"), QColor("#7A3B00"), QColor("#2980B9"),
                QColor("#5B4BD6"), QColor("#2C7A7A"), QColor("#232627"), QColor("#7C3B43"), QColor("#2E5C3F"),
                QColor("#5B3E1E"), QColor("#2F5F82"), QColor("#4C4294"), QColor("#2F5656"), QColor("#232627"), QColor("#232627")};
    }

private Q_SLOTS:
    void everySlotIsLegible_data()
    {
        QTest::addColumn<bool>("dark");
        QTest::newRow("light") << false;
        QTest::newRow("dark") << true;
    }
    void everySlotIsLegible()
    {
        QFETCH(bool, dark);
        const QColor surface = dark ? QColor("#1b1e20") : QColor("#f4f4fa");
        const QColor text = dark ? QColor("#fcfcfc") : QColor("#232627");
        ConsoleTheme t;
        t.build(sample(dark), text, surface, false);
        for (int i = 0; i < PaletteSlots; ++i) {
            QVERIFY2(contrastRatio(t.slot(i), surface) >= 4.5, qPrintable(QStringLiteral("slot %1: %2").arg(i).arg(contrastRatio(t.slot(i), surface))));
            QCOMPARE(t.slot(i).alpha(), 255);
        }
        // the ramp goes from slot 0 toward the text
        QVERIFY(contrastRatio(t.slot(23), surface) >= contrastRatio(t.slot(16), surface) - 0.01);
        // a missing colour is the text colour
        ConsoleTheme few;
        few.build({}, text, surface, false);
        QCOMPARE(few.slot(3), text);
    }

    void backgroundsKeepTextLegible()
    {
        for (const bool dark : {false, true}) {
            const QColor surface = dark ? QColor("#1b1e20") : QColor("#f4f4fa");
            const QColor text = dark ? QColor("#fcfcfc") : QColor("#232627");
            ConsoleTheme t;
            t.build(sample(dark), text, surface, false);
            for (int bg = 0; bg < PaletteSlots; ++bg) {
                for (int fg = -1; fg < PaletteSlots; ++fg) {
                    Style s;
                    s.bg = quint8(bg);
                    s.fg = fg < 0 ? NoColor : quint8(fg);
                    const QTextCharFormat f = t.format(s);
                    const QColor back = f.background().color();
                    const QColor front = f.foreground().style() == Qt::NoBrush ? text : f.foreground().color();
                    QVERIFY2(contrastRatio(front, back) >= 4.5, qPrintable(QStringLiteral("dark %1 fg %2 bg %3: %4").arg(dark).arg(fg).arg(bg).arg(contrastRatio(front, back))));
                }
            }
            // inverse
            for (int fg = -1; fg < PaletteSlots; ++fg) {
                Style s;
                s.fg = fg < 0 ? NoColor : quint8(fg);
                s.flags = Inverse;
                const QTextCharFormat f = t.format(s);
                QVERIFY(contrastRatio(f.foreground().color(), f.background().color()) >= 4.5);
            }
        }
    }

    void highContrastHasNoColour()
    {
        ConsoleTheme t;
        t.build(sample(false), QColor("#000000"), QColor("#ffffff"), true);
        Style s;
        s.fg = 1;
        s.bg = 2;
        s.flags = Bold | Italic | Underline | Strike | Dim;
        QTextCharFormat f = t.format(s);
        QCOMPARE(f.foreground().style(), Qt::NoBrush);
        QCOMPARE(f.background().style(), Qt::NoBrush);
        QVERIFY(f.fontWeight() >= QFont::Bold);
        QVERIFY(f.fontItalic());
        QVERIFY(f.fontUnderline());
        QVERIFY(f.fontStrikeOut());
        s = Style();
        s.flags = Inverse;
        f = t.format(s);
        QVERIFY(f.fontWeight() >= QFont::Bold);
        QVERIFY(f.fontUnderline());
        QCOMPARE(f.background().style(), Qt::NoBrush);
    }

    void flagsMapToTheFormat()
    {
        ConsoleTheme t;
        t.build(sample(false), QColor("#232627"), QColor("#f4f4fa"), false);
        QVERIFY(t.format(Style()).isEmpty());
        Style s;
        s.flags = Bold;
        QVERIFY(t.format(s).fontWeight() >= QFont::Bold);
        s.flags = Italic;
        QVERIFY(t.format(s).fontItalic());
        s.flags = Underline;
        QVERIFY(t.format(s).fontUnderline());
        s.flags = Strike;
        QVERIFY(t.format(s).fontStrikeOut());
        s.flags = Dim;
        QVERIFY(contrastRatio(t.format(s).foreground().color(), QColor("#f4f4fa")) < contrastRatio(QColor("#232627"), QColor("#f4f4fa")));
    }
};

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    int rc = 0;
    {
        TestAnsiParser t;
        rc |= QTest::qExec(&t, argc, argv);
    }
    {
        TestConsoleTheme t;
        rc |= QTest::qExec(&t, argc, argv);
    }
    return rc;
}

#include "tst_ansiparser.moc"
