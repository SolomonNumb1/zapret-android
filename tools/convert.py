#!/usr/bin/env python3
"""Convert Flowseal winws .bat strategies to Linux nfqws configs.

Rules:
- drop winws/Windows-only options (--wf-tcp/--wf-udp)
- drop whole profiles that relied on --ipset (stock Android kernels have no ipset)
- drop game-filter profiles (use %GameFilterTCP%/UDP variables)
- strip %BIN% / %LISTS% prefixes, make payload/hostlist paths relative to bin/
"""
import os, re, sys

SRC = "/data/data/com.termux/files/home/zapret-android/strategies/bat"
HEADER = (
    "--qnum=200",
    "--bind-fix4",
    "--bind-fix6",
    "--uid=1:3003",
    "--daemon",
    "--pidfile=nfqws.pid",
    "--debug=@nfqws.log",
)
DROP_OPTS = {"--wf-tcp", "--wf-udp", "--filter-ssid", "--ipset-exclude-ip"}
KNOWN_LISTS = {
    "list-general.txt", "list-google.txt", "list-exclude.txt",
    "ipset-all.txt", "ipset-exclude.txt",
}
# Рядом с основным списком подключаем и user-версию (пользовательские домены).
# Файл всегда должен существовать в рантайме (создаёт install.sh), может быть пустым.
USER_LISTS = {
    "lists/list-general.txt": "lists/list-general-user.txt",
    "lists/list-exclude.txt": "lists/list-exclude-user.txt",
    "lists/ipset-exclude.txt": "lists/ipset-exclude-user.txt",
}
# Читаемые имена вместо general___ALT11__.conf и т.п.
RENAME = {
    "general.bat": "general.conf",
    "general___ALT__.bat": "alt.conf",
    "general___ALT2__.bat": "alt2.conf",
    "general___ALT3__.bat": "alt3.conf",
    "general___ALT4__.bat": "alt4.conf",
    "general___ALT5__.bat": "alt5.conf",
    "general___ALT6__.bat": "alt6.conf",
    "general___ALT7__.bat": "alt7.conf",
    "general___ALT8__.bat": "alt8.conf",
    "general___ALT9__.bat": "alt9.conf",
    "general___ALT10__.bat": "alt10.conf",
    "general___ALT11__.bat": "alt11.conf",
    "general___ALT12__.bat": "alt12.conf",
    "general___EXP__.bat": "exp.conf",
    "general___FAKE_TLS_AUTO__.bat": "fake-tls-auto.conf",
    "general___FAKE_TLS_AUTO_ALT__.bat": "fake-tls-auto-alt.conf",
    "general___FAKE_TLS_AUTO_ALT2__.bat": "fake-tls-auto-alt2.conf",
    "general___FAKE_TLS_AUTO_ALT3__.bat": "fake-tls-auto-alt3.conf",
    "general___SIMPLE_FAKE__.bat": "simple-fake.conf",
    "general___SIMPLE_FAKE_ALT__.bat": "simple-fake-alt.conf",
    "general___SIMPLE_FAKE_ALT2__.bat": "simple-fake-alt2.conf",
}
PAYLOAD_OPTS = {
    "--dpi-desync-fake-tls", "--dpi-desync-fake-quic", "--dpi-desync-fake-http",
    "--dpi-desync-fake-discord", "--dpi-desync-fake-stun", "--dpi-desync-fake-unknown",
    "--dpi-desync-fake-unknown-udp", "--dpi-desync-split-seqovl-pattern",
}


def tokenize(args):
    return [t.strip('"').lstrip("^") for t in re.findall(r'"[^"]*"|\S+', args)]


def parse(bat):
    text = re.sub(r"\^\r?\n", " ", bat)
    m = re.search(r'winws\.exe"\s+(.+)', text, re.S)
    if not m:
        return None
    return tokenize(m.group(1))


def split_profiles(toks):
    profiles, cur = [], []
    for t in toks:
        if t == "--new":
            if cur:
                profiles.append(cur)
                cur = []
        elif t == "--skip":
            continue
        else:
            cur.append(t)
    if cur:
        profiles.append(cur)
    return profiles


def profile_to_args(toks):
    out = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if not t.startswith("--"):
            i += 1
            continue
        name = t.split("=", 1)[0]
        if name in DROP_OPTS:
            i += 1
            continue
        if "=" in t:
            _, val = t.split("=", 1)
            i += 1
        elif i + 1 < len(toks) and not toks[i + 1].startswith("--"):
            val = toks[i + 1]
            i += 2
        else:
            val = None
            i += 1
        if val is None:
            out.append(name)
            continue
        # expand %BIN%/%LISTS% and cleanup
        v = val.replace("%BIN%", "").replace("%LISTS%", "").lstrip("^")
        if v.startswith('"'):
            v = v[1:]
        # payload / hostlist -> relative path
        if name in PAYLOAD_OPTS:
            if v.startswith(("0x", "!")) or v in ("-", "~"):
                v = v
            else:
                v = "bin/" + os.path.basename(v)
        elif name in ("--hostlist", "--hostlist-exclude", "--ipset", "--ipset-exclude"):
            base = os.path.basename(v)
            if "user" in base or base not in KNOWN_LISTS:
                continue
            v = "lists/" + base
        out.append(f"{name}={v}")
        if v in USER_LISTS:
            out.append(f"{name}={USER_LISTS[v]}")
    return out


def clean(toks):
    out = []
    for t in toks:
        name = t.split("=", 1)[0]
        if name in DROP_OPTS:
            continue
        if t.startswith("--wf-"):
            continue
        out.append(t)
    return out


def render(profiles):
    blocks = []
    for toks in profiles:
        toks = clean(toks)
        if any("GameFilter" in t for t in toks):
            continue
        args = profile_to_args(toks)
        if not args:
            continue
        blocks.append("\n".join(args))
    body = "\n--new\n".join(blocks)
    if not body:
        return ""
    return "\n".join(HEADER) + "\n" + body


def main():
    os.makedirs(OUT, exist_ok=True)
    for fn in sorted(os.listdir(SRC)):
        if not fn.endswith(".bat"):
            continue
        with open(os.path.join(SRC, fn)) as f:
            text = f.read()
        toks = parse(text)
        if toks is None:
            print("PARSE FAIL", fn)
            continue
        profiles = split_profiles(toks)
        rendered = render(profiles)
        if not rendered:
            print("SKIP EMPTY", fn)
            continue
        name = RENAME.get(fn, fn[:-4] + ".conf")
        with open(os.path.join(OUT, name), "w") as f:
            f.write(rendered + "\n")
        print(f"{name}: {len(profiles)} profiles -> {rendered.count('--new') + 1} kept")


OUT = "/data/data/com.termux/files/home/zapret-android/strategies"
if __name__ == "__main__":
    main()
