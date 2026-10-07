#include "legacyconfig.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStringConverter>

#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace LegacyConfig
{
QString renameGroup(const QString &text)
{
    static const QLatin1String old("[Atlas]");
    QString out;
    out.reserve(text.size() + 16);
    qsizetype pos = 0;
    while (pos < text.size()) {
        qsizetype end = text.indexOf(QLatin1Char('\n'), pos);
        end = end < 0 ? text.size() : end + 1;
        const QStringView line = QStringView(text).mid(pos, end - pos);
        if (line.startsWith(old)) {
            const QStringView rest = line.mid(old.size());
            if (rest.trimmed().isEmpty() || rest.startsWith(QLatin1Char('['))) {
                out += QLatin1String("[Telamon]");
                out += rest;
                pos = end;
                continue;
            }
        }
        out += line;
        pos = end;
    }
    return out;
}

namespace
{
bool writeAll(int fd, const QByteArray &data)
{
    qsizetype done = 0;
    while (done < data.size()) {
        const ssize_t n = ::write(fd, data.constData() + done, size_t(data.size() - done));
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        done += n;
    }
    return ::fsync(fd) == 0;
}

// Reads a regular file of at most maxBytes without blocking on a fifo.
bool readRegular(const QByteArray &path, qint64 maxBytes, QByteArray *data, mode_t *mode)
{
    const int fd = ::open(path.constData(), O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC);
    if (fd < 0) {
        return false;
    }
    struct stat st;
    bool ok = ::fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_size <= maxBytes;
    if (ok) {
        *mode = st.st_mode & 0777;
        data->clear();
        char buf[16384];
        for (;;) {
            const ssize_t n = ::read(fd, buf, sizeof buf);
            if (n < 0 && errno == EINTR) {
                continue;
            }
            if (n <= 0) {
                ok = n == 0;
                break;
            }
            data->append(buf, n);
            if (data->size() > maxBytes) {
                ok = false;
                break;
            }
        }
    }
    ::close(fd);
    return ok;
}

// A new file at `path`, made exclusively, holding `data` with `mode`.
bool createExclusive(const QByteArray &path, const QByteArray &data, mode_t mode)
{
    const int fd = ::open(path.constData(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode);
    if (fd < 0) {
        return false;
    }
    // The umask may have taken bits off.
    const bool ok = ::fchmod(fd, mode) == 0 && writeAll(fd, data);
    ::close(fd);
    if (!ok) {
        ::unlink(path.constData());
    }
    return ok;
}
}

bool adoptFile(const QString &newPath, const QString &oldPath, qint64 maxBytes)
{
    const QByteArray newName = QFile::encodeName(newPath);
    struct stat st;
    if (::lstat(newName.constData(), &st) == 0) {
        return false;
    }
    QByteArray data;
    mode_t mode = 0600;
    if (!readRegular(QFile::encodeName(oldPath), maxBytes, &data, &mode)) {
        return false;
    }
    // Not UTF-8: copied as it is.
    QStringDecoder decoder(QStringDecoder::Utf8, QStringConverter::Flag::Stateless);
    const QString text = decoder(data);
    const QByteArray out = decoder.hasError() ? data : renameGroup(text).toUtf8();

    const QFileInfo info(newPath);
    if (!QDir().mkpath(info.path())) {
        return false;
    }
    const QByteArray tmp = QFile::encodeName(info.path() + QLatin1String("/.") + info.fileName() + QLatin1String(".adopt") + QString::number(::getpid()));
    ::unlink(tmp.constData());
    if (!createExclusive(tmp, out, mode)) {
        return false;
    }
    bool made;
    if (::link(tmp.constData(), newName.constData()) == 0) {
        made = true;
    } else if (errno == EEXIST) {
        made = false;
    } else {
        // No hard links here: make the name exclusively instead.
        made = createExclusive(newName, out, mode);
    }
    ::unlink(tmp.constData());
    return made;
}

QByteArray env(const char *telamon, const char *atlas)
{
    return qEnvironmentVariableIsSet(telamon) ? qgetenv(telamon) : qgetenv(atlas);
}
}
