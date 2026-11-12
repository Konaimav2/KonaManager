# Builds the good and evil zips used by tests/run.sh.  Usage: python3 -I mkzips.py <empty outdir>
import hashlib, os, sys, zipfile

out = sys.argv[1]
os.makedirs(out, exist_ok=True)

def sha(b): return hashlib.sha256(b).hexdigest()

INSTALL = b"#!/bin/sh\necho installed > \"$KM_DAEMON_DIR/installed.txt\"\nexit 0\n"
UNINSTALL = b"#!/bin/sh\necho gone > \"$KM_ROOT/uninstalled.txt\"\nexit 0\n"
START = b"#!/bin/sh\nwhile :; do sleep 1; done\n"

def manifest(id="km-test-pkg", extra=None, pin=True, hooks=True):
    lines = ["schema=1", "id=" + id, "name=Test Package", "desc=fixture package", "version=1.2.3",
             "kind=daemon", "start=start.sh", "stop_grace=2", "start_timeout=6"]
    if hooks and pin:
        lines += ["hooks.install.sha256=" + sha(INSTALL), "hooks.uninstall.sha256=" + sha(UNINSTALL)]
    lines += extra or []
    return ("\n".join(lines) + "\n").encode()

def build(name, entries, method=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(os.path.join(out, name), "w", method) as z:
        for e in entries:
            if len(e) == 2:
                z.writestr(e[0], e[1])
            else:
                z.writestr(e[0], e[1])  # ZipInfo given
    return name

def base(id="km-test-pkg", **kw):
    ents = [("daemon.meta", manifest(id, **kw)), ("start.sh", START),
            ("hooks/install.sh", INSTALL), ("hooks/uninstall.sh", UNINSTALL),
            ("files/readme.txt", b"hello\n")]
    return ents

build("good.zip", base())
build("good-nohook.zip", [("daemon.meta", manifest("km-test-plain", hooks=False)), ("start.sh", START)])
build("unpinned.zip", base("km-test-unpinned", pin=False))
build("badid.zip", base("Bad_ID"))
build("badid2.zip", base("a"))
build("dotdot.zip", base() + [("../evil.txt", b"x")])
build("dotdot-deep.zip", base() + [("files/../../../evil.txt", b"x")])
build("absolute.zip", base() + [("/tmp/km-evil-abs.txt", b"x")])
build("backslash.zip", base() + [("a\\..\\b", b"x")])
build("specialchars.zip", base() + [("sp ace;rm.txt", b"x")])

zi = zipfile.ZipInfo("link"); zi.create_system = 3; zi.external_attr = (0o120777 << 16)
with zipfile.ZipFile(os.path.join(out, "symlink.zip"), "w") as z:
    for n, d in base(): z.writestr(n, d)
    z.writestr(zi, "/etc")

zi = zipfile.ZipInfo("dev"); zi.create_system = 3; zi.external_attr = (0o020666 << 16)
with zipfile.ZipFile(os.path.join(out, "device.zip"), "w") as z:
    for n, d in base(): z.writestr(n, d)
    z.writestr(zi, b"")

with zipfile.ZipFile(os.path.join(out, "oversize.zip"), "w", zipfile.ZIP_STORED) as z:
    for n, d in base(): z.writestr(n, d)
    z.writestr("files/big.bin", os.urandom(6 * 1024 * 1024))

build("many.zip", base() + [("files/f%03d.txt" % i, b"x") for i in range(200)])   # 5 + 200 = 205 entries
build("limit.zip", [("daemon.meta", manifest("km-test-limit", hooks=False)), ("start.sh", START)] + [("files/f%03d.txt" % i, b"x") for i in range(198)])  # exactly 200

with zipfile.ZipFile(os.path.join(out, "bomb.zip"), "w", zipfile.ZIP_DEFLATED) as z:
    for n, d in base(): z.writestr(n, d)
    z.writestr("files/zeros.bin", b"\0" * (25 * 1024 * 1024))

bad_pin = manifest("km-test-badhash").replace(sha(INSTALL).encode(), b"0" * 64)
build("hashmismatch.zip", [("daemon.meta", bad_pin), ("start.sh", START), ("hooks/install.sh", INSTALL), ("hooks/uninstall.sh", UNINSTALL)])
build("nomanifest.zip", [("start.sh", START)])
build("startmissing.zip", [("daemon.meta", manifest("km-test-nostart", hooks=False))])
build("startabs.zip", [("daemon.meta", manifest("km-test-abs", hooks=False).replace(b"start=start.sh", b"start=/bin/sh")), ("start.sh", START)])
build("startdots.zip", [("daemon.meta", manifest("km-test-dots", hooks=False).replace(b"start=start.sh", b"start=../start.sh")), ("start.sh", START)])

FAILHOOK = b"#!/bin/sh\nexit 5\n"
fm = manifest("km-test-failhook", hooks=False) + b"hooks.install.sha256=" + sha(FAILHOOK).encode() + b"\n"
build("failhook.zip", [("daemon.meta", fm), ("start.sh", START), ("hooks/install.sh", FAILHOOK)])

build("builtin-id.zip", [("daemon.meta", manifest("appguard", hooks=False)), ("start.sh", START)])
build("notzip.zip", [("x", b"x")])
with open(os.path.join(out, "garbage.zip"), "wb") as f: f.write(os.urandom(4096))
