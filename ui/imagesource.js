.pragma library

// The check behind the picture of TelamonAvatar and TelamonChoiceCard: the
// same rule as TelamonScreenshotCarousel's. A source the app got from outside
// (a user's picture, a link in some metadata) loads a local file, a qrc: or
// image: resource; an https: address only when the app set `allowRemote` for a
// trusted source; nothing else (no http:, no ftp:, no UNC path, no control
// characters). The url returned is the one the Image loads, resolved here, so
// the check and the load cannot read the source two ways. "" for a source
// that is refused or empty.
function vetted(source, allowRemote) {
    if (source === undefined || source === null || Array.isArray(source)
            || (typeof source !== "string" && typeof source !== "object")) {
        return "";
    }
    const text = String(source);
    // Leading spaces (which Qt drops before the scheme), "//host" and "\\host",
    // and control characters (C0, DEL, C1) anywhere.
    if (text === "" || text.length > 8192 || /^[\s\u0085﻿]/.test(text)
            || /^[\/\\]{2}/.test(text) || /[\x00-\x1f\x7f-\x9f]/.test(text)) {
        return "";
    }
    const resolved = Qt.resolvedUrl(text).toString();
    const m = /^([a-z][a-z0-9+.-]*):/i.exec(resolved);
    if (!m) {
        return "";
    }
    const scheme = m[1].toLowerCase();
    if (scheme === "file") {
        return /^file:(\/\/(localhost)?)?\/(?![\/\\])/i.test(resolved) ? resolved : "";
    }
    if (scheme === "qrc" || scheme === "image" || (scheme === "https" && allowRemote === true)) {
        return resolved;
    }
    return "";
}
