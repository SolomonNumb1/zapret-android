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
        name = fn[:-4] + ".conf"
        with open(os.path.join(OUT, name), "w") as f:
            f.write(rendered + "\n")
        print(f"{name}: {len(profiles)} profiles -> {rendered.count('--new') + 1} kept")


OUT = "/data/data/com.termux/files/home/zapret-android/strategies"
if __name__ == "__main__":
    main()
