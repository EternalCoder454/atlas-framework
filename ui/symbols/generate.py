#!/usr/bin/env python3
"""Update Telamon.Ui's symbols from a Google Fonts download of Material Symbols.

    uv run --with fonttools ui/symbols/generate.py <download.zip>

The zip is what fonts.google.com gives for Material Symbols Outlined, Rounded
and Sharp together (one family alone works too, but all three must be there
before an update ships). It writes, next to this script:

  TelamonSymbols{Outlined,Rounded,Sharp}.ttf    the variable fonts, renamed (see
                                                rename_family)
  LICENSE.txt                                   their licence (Apache 2.0)
  symbolnames.h                                 the Symbols.<Name> enum
  symboltable.inc                               name -> codepoint, for lookups

symbolnames.h and symboltable.inc are generated: edit this script, not them.
"""

import re
import sys
import zipfile
from io import BytesIO
from pathlib import Path

from fontTools.ttLib import TTFont

HERE = Path(__file__).resolve().parent
STYLES = ("Outlined", "Rounded", "Sharp")

# Names that start with a number get it spelled out, since an enum key can't
# start with a digit ("10k" is TenK). These read better whole.
WHOLE = {"123": "OneTwoThree", "360": "ThreeSixty"}
ONES = "Zero One Two Three Four Five Six Seven Eight Nine Ten Eleven Twelve Thirteen Fourteen Fifteen Sixteen Seventeen Eighteen Nineteen".split()
TENS = "_ _ Twenty Thirty Forty Fifty Sixty Seventy Eighty Ninety".split()


def number_words(n: int) -> str:
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10] + (ONES[n % 10] if n % 10 else "")
    if n < 1000:
        return ONES[n // 100] + "Hundred" + (number_words(n % 100) if n % 100 else "")
    sys.exit(f"generate.py: no words for {n}")


def enum_key(name: str) -> str:
    """arrow_back -> ArrowBack, 10k -> TenK, 3d_rotation -> ThreeDRotation."""
    if name in WHOLE:
        return WHOLE[name]
    parts = name.split("_")
    m = re.fullmatch(r"(\d+)([a-z]*)", parts[0])
    if m:
        parts[0:1] = [number_words(int(m.group(1)))] + ([m.group(2)] if m.group(2) else [])
    return "".join(p[:1].upper() + p[1:] for p in parts)


def rename_family(data: bytes) -> bytes:
    """The font with its names changed from "Material Symbols <Style>" to
    "Telamon Symbols <Style>" (family, full and PostScript names), and nothing
    else changed. Telamon.Ui asks for that family, so it never picks up (or is
    picked up by) the Material Symbols fonts of the Atlas.Ui 1.x packages,
    which stay installable beside this one. The Apache-2.0 licence allows it."""
    font = TTFont(BytesIO(data))
    for record in font["name"].names:
        text = record.toUnicode()
        if "Material" in text:
            record.string = text.replace("Material Symbols", "Telamon Symbols").replace("MaterialSymbols", "TelamonSymbols")
    out = BytesIO()
    font.save(out)
    return out.getvalue()


def read_symbols(font: TTFont):
    """(name -> codepoint, alias -> name). Names as Google lists them."""
    cmap = font.getBestCmap()
    glyph_cp = {g: c for c, g in cmap.items() if c >= 0xE000}
    # The fonts' glyph names are the symbol names, with a leading underscore
    # on the ones that start with a digit ("_10k" is "10k").
    names = {g.lstrip("_"): c for g, c in glyph_cp.items()}
    if len(names) != len(glyph_cp) or len(set(names.values())) != len(names):
        sys.exit("generate.py: two symbols share a name or a codepoint")
    # Older names still typed into the font as ligatures ("check_circle_outline"
    # draws check_circle): lookups by name accept them too.
    first = {}
    for c, g in cmap.items():
        first.setdefault(g, c)
    aliases = {}
    for lookup in font["GSUB"].table.LookupList.Lookup:
        for st in lookup.SubTable:
            if st.LookupType == 7:
                st = st.ExtSubTable
            for start, ligs in getattr(st, "ligatures", {}).items():
                for lig in ligs:
                    if lig.LigGlyph not in glyph_cp:
                        continue
                    chars = [first.get(g) for g in [start, *lig.Component]]
                    if None in chars:
                        sys.exit(f"generate.py: a ligature for {lig.LigGlyph} uses a glyph with no character")
                    text = "".join(map(chr, chars)).lower()
                    target = lig.LigGlyph.lstrip("_")
                    if text == target or text in names:
                        continue
                    if aliases.get(text, target) != target:
                        sys.exit(f"generate.py: {text} names both {aliases[text]} and {target}")
                    aliases[text] = target
    return names, aliases


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    fonts = {}
    licence = None
    with zipfile.ZipFile(sys.argv[1]) as z:
        for info in z.infolist():
            path = info.filename
            m = re.fullmatch(r"Material_Symbols_(\w+)/MaterialSymbols\1-VariableFont_[^/]*\.ttf", path)
            if m and m.group(1) in STYLES:
                fonts[m.group(1)] = z.read(info)
            elif path.endswith("/LICENSE.txt") and licence is None:
                licence = z.read(info)
    if not fonts:
        sys.exit("generate.py: no Material Symbols variable fonts in that zip")
    missing = [s for s in STYLES if s not in fonts]
    if missing:
        print(f"generate.py: warning: no {', '.join(missing)} in the zip; keeping the old files", file=sys.stderr)

    tables = {}
    version = None
    for style, data in fonts.items():
        font = TTFont(BytesIO(data), lazy=True)
        axes = {a.axisTag for a in font["fvar"].axes}
        if axes != {"FILL", "GRAD", "opsz", "wght"}:
            sys.exit(f"generate.py: {style} has axes {sorted(axes)}")
        tables[style] = read_symbols(font)
        version = font["name"].getDebugName(5)
    first_style = next(iter(tables))
    names, aliases = tables[first_style]
    for style, (n, _) in tables.items():
        if n != names:
            sys.exit(f"generate.py: {style} has different symbols from {first_style}")

    # "Name" is the enum's own name.
    keys = {"Name": "(the enum)"}
    for name in names:
        key = enum_key(name)
        if key in keys:
            sys.exit(f"generate.py: {name} and {keys[key]} would both be Symbols.{key}")
        keys[key] = name

    for style, data in fonts.items():
        (HERE / f"TelamonSymbols{style}.ttf").write_bytes(rename_family(data))
    if licence:
        (HERE / "LICENSE.txt").write_bytes(licence)

    header = f"// Generated by ui/symbols/generate.py from Material Symbols ({version}). Do not edit.\n"
    by_name = sorted(names.items())
    with open(HERE / "symbolnames.h", "w") as f:
        f.write(header)
        f.write("// Every symbol as Symbols.<Name>, whose value is its codepoint in the fonts.\n")
        f.write("#pragma once\n\n#include <QObject>\n\nnamespace SymbolNames\n{\nQ_NAMESPACE\n\nenum Name : int {\n")
        for name, cp in by_name:
            f.write(f"    {enum_key(name)} = 0x{cp:x}, // {name}\n")
        f.write("};\nQ_ENUM_NS(Name)\n}\n")
    table = sorted([(n, c, "false") for n, c in names.items()] + [(a, names[t], "true") for a, t in aliases.items()])
    with open(HERE / "symboltable.inc", "w") as f:
        f.write(header)
        f.write("// Names (and older aliases) to codepoints, sorted by name for a binary search.\n")
        for name, cp, alias in table:
            f.write(f'    {{"{name}", 0x{cp:x}, {alias}}},\n')
    print(f"{len(names)} symbols, {len(aliases)} aliases, from {', '.join(fonts)} ({version})")


if __name__ == "__main__":
    main()
