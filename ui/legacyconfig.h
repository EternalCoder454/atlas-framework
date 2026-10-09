// What Telamon.Ui 2.0.0 still reads from before the rename (it was Atlas.Ui):
// a file under its old name, and the environment variables that people set
// by hand. One-way, and only when the new name is absent: the old file is
// copied (an app that has not moved yet keeps using it), never changed.
#pragma once

#include <QByteArray>
#include <QString>

namespace LegacyConfig
{
// `text` with every `[Atlas]` group header (also `[Atlas][$i]`, `[Atlas][Sub]`)
// renamed to `[Telamon]`; every other byte unchanged.
QString renameGroup(const QString &text);

// Copies `oldPath` to `newPath`, renaming the `[Atlas]` group, when nothing is
// at `newPath` (not even a link) and `oldPath` is a regular file (or a link
// to one) of at most `maxBytes`. The copy keeps the mode (without write access for the group and others), is complete before
// it appears under its name and never replaces a file another process made in
// the meantime. Returns whether a file was made. Bytes that are not UTF-8 are
// copied as they are.
bool adoptFile(const QString &newPath, const QString &oldPath, qint64 maxBytes = 4 * 1024 * 1024);

// The value of `telamon` (e.g. TELAMON_LOG), else that of `atlas`
// (ATLAS_LOG), the name before 2.0.0. "Else" means the first is not set at
// all: an empty TELAMON_X is an answer.
QByteArray env(const char *telamon, const char *atlas);
}
