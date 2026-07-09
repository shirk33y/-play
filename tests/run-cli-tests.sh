#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/play-tests.$$"; FAKE="$TMP/fakebin"; LIB="$TMP/library"; FAST_LIB="$TMP/fast-library"; NAT_LIB="$TMP/nat-library"; HOME_DIR="$TMP/home"
export HOME="$HOME_DIR" SYNC_DIR="$HOME_DIR/.-sync" MPV_LOG="$TMP/mpv.log" STAT_LOG="$TMP/stat.log" PATH="$FAKE:$PATH"
pass=0
log(){ printf '%s\n' "$*" >&2; }
ok(){ pass=$((pass+1)); log "ok  $*"; }
bad(){ log "not ok  $*"; exit 1; }
assert_eq(){ [[ "$2" == "$1" ]] && ok "$3" || bad "$3: expected [$1], got [$2]"; }
assert_gt(){ (( $1 > $2 )) && ok "$3" || bad "$3: expected > $2, got $1"; }
cleanup(){ [[ "${KEEP_TEST_TMP:-0}" == 1 ]] && log "KEEP_TEST_TMP=$TMP" || rm -rf -- "$TMP"; }
trap cleanup EXIT
mkdir -p "$FAKE" "$LIB/images" "$LIB/videos" "$LIB/mixed/a" "$LIB/mixed/b" "$FAST_LIB/a" "$FAST_LIB/b" "$NAT_LIB" "$SYNC_DIR" "$HOME_DIR"
: > "$STAT_LOG"; : > "$MPV_LOG"
cat > "$FAKE/gawk" <<'EOF'
#!/usr/bin/env bash
exec awk "$@"
EOF
chmod +x "$FAKE/gawk"
cat > "$FAKE/stat" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STAT_LOG:-/dev/null}"
exec /usr/bin/stat "$@"
EOF
chmod +x "$FAKE/stat"
cat > "$FAKE/fd" <<'PY'
#!/usr/bin/env python3
import os, re, sys
args=sys.argv[1:]; abs_paths=False; null=False; exts=[]; pattern='.'; roots=[]; i=0
while i < len(args):
    a=args[i]
    if a=='-a': abs_paths=True; i+=1
    elif a=='-0': null=True; i+=1
    elif a=='-t': i+=2
    elif a=='-e': exts.append(args[i+1].lower()); i+=2
    elif a=='--ignore-file': i+=2
    elif a in ('-H','--hidden'): i+=1
    elif a in ('-d','--max-depth'): i+=2
    elif a.startswith('-'): i+=1
    else: pattern=a; roots=args[i+1:] or ['.']; break
rx=None if pattern in ('','.') else re.compile(pattern); out=[]
for root in roots or ['.']:
    root=os.path.abspath(os.path.expanduser(root)); files=[]
    if os.path.isfile(root): files=[root]
    else:
        for dp,_,fs in os.walk(root):
            for n in fs: files.append(os.path.join(dp,n))
    for p in files:
        e=p.rsplit('.',1)[-1].lower() if '.' in os.path.basename(p) else ''
        if exts and e not in exts: continue
        target=os.path.abspath(p) if abs_paths else os.path.relpath(p)
        if rx and not rx.search(target): continue
        out.append(target)
out.sort(); sep='\0' if null else '\n'; sys.stdout.write(sep.join(out));
if out and not null: sys.stdout.write('\n')
PY
chmod +x "$FAKE/fd"
cat > "$FAKE/parallel" <<'PY'
#!/usr/bin/env python3
import os, sys
args=sys.argv[1:]; null=False; cmd=[]; i=0
while i < len(args):
    a=args[i]
    if a=='--will-cite': i+=1
    elif a=='-0': null=True; i+=1
    elif a=='-j': i+=2
    elif a=='--colsep': i+=2
    elif a=='--': cmd=args[i+1:]; break
    else: i+=1
if '::::' in cmd:
    k=cmd.index('::::'); data=open(cmd[k+1],'rb').read(); cmd=cmd[:k]
else: data=sys.stdin.buffer.read()
image=set(os.environ.get('IMAGE_EXTS','').split()); video=set(os.environ.get('VIDEO_EXTS','').split())
def kind(path):
    e=os.path.basename(path).rsplit('.',1)[-1].lower() if '.' in os.path.basename(path) else ''
    if e in image: return 'image',e
    if e in video: return 'video',e
    return 'other',e
if len(cmd)>=2 and cmd[1]=='__stat':
    for raw in (data.split(b'\0') if null else data.splitlines()):
        if not raw: continue
        p=raw.decode(); k,e=kind(p)
        if k=='other' or not os.path.isfile(p): continue
        st=os.stat(p); print(f'sync: stat {p}', file=sys.stderr)
        print(f'{st.st_dev}:{st.st_ino}\t{p}\t{st.st_size}\t{int(st.st_mtime)}000000000\t{int(st.st_ctime)}000000000\t{k}\t{e}')
elif len(cmd)>=2 and cmd[1]=='__probe':
    rows=data.decode().splitlines()
    for row in rows:
        c=row.split('\t'); c += ['']*(15-len(c)); _,id,p,size,mtime,ctime,k,e,w,h,d,b,mp,anim,hs=c[:15]
        print(f'sync: no-probe {p}', file=sys.stderr)
        print('\t'.join([id,p,size,mtime,ctime,k,e,w,h,d,b,mp,anim,hs,'0']))
else: sys.exit('fake parallel unsupported')
PY
chmod +x "$FAKE/parallel"
cat > "$FAKE/mpv" <<'EOF'
#!/usr/bin/env bash
printf '%q ' "$@" >> "${MPV_LOG:-/dev/null}"; printf '\n' >> "${MPV_LOG:-/dev/null}"
EOF
chmod +x "$FAKE/mpv"

printf jpg > "$LIB/images/a.jpg"; printf mp4 > "$LIB/videos/a.mp4"; printf gif > "$LIB/mixed/a/a.gif"; printf webm > "$LIB/mixed/b/a.webm"; truncate -s 25M "$LIB/videos/large.mp4"; truncate -s 30M "$LIB/images/large.jpg"; printf bad > "$LIB/nope.txt"
for i in $(seq -w 1 750); do printf x > "$FAST_LIB/a/img_$i.jpg"; printf x > "$FAST_LIB/b/vid_$i.mp4"; done
printf x > "$NAT_LIB/image12.jpg"; printf x > "$NAT_LIB/image1.jpg"; printf x > "$NAT_LIB/image2.jpg"

bash -n "$ROOT/bin/-play" "$ROOT/bin/-sync" "$ROOT/bin/bench-play" "$ROOT/install.sh" "$ROOT/uninstall.sh"; ok "bash syntax"
source "$ROOT/completion/bash.sh"; complete -p -- -play >/dev/null && complete -p -- -sync >/dev/null && ok "bash completion registered" || bad "completion"
: > "$STAT_LOG"; "$ROOT/bin/-play" -l "$LIB" >/tmp/all.out 2>"$TMP/all.err"; assert_eq 6 "$(sed '/^$/d' /tmp/all.out|wc -l|tr -d ' ')" "-play fast count"; assert_eq 0 "$(wc -l < "$STAT_LOG"|tr -d ' ')" "-play fast no stat"; grep -q 'fast path' "$TMP/all.err" && ok "-play fast log" || bad "fast log"
: > "$STAT_LOG"; "$ROOT/bin/-play" -l "$FAST_LIB" >/tmp/big.out 2>"$TMP/big.err"; assert_eq 1500 "$(sed '/^$/d' /tmp/big.out|wc -l|tr -d ' ')" "-play large fast count"; assert_eq 0 "$(wc -l < "$STAT_LOG"|tr -d ' ')" "-play large no stat"
: > "$STAT_LOG"; "$ROOT/bin/-play" -l "$NAT_LIB" >/tmp/nat.out 2>"$TMP/nat.err"; expected_nat="$(printf "%s\n%s\n%s\n" "$NAT_LIB/image1.jpg" "$NAT_LIB/image2.jpg" "$NAT_LIB/image12.jpg")"; actual_nat="$(cat /tmp/nat.out)"; assert_eq "$expected_nat" "$actual_nat" "-play natural sort"; assert_eq 0 "$(wc -l < "$STAT_LOG"|tr -d ' ')" "-play natural sort no stat"
: > "$STAT_LOG"; "$ROOT/bin/-play" -l -s +20M "$LIB" >/tmp/size.out 2>"$TMP/size.err"; assert_gt "$(wc -l < "$STAT_LOG"|tr -d ' ')" 0 "-play size uses stat"; assert_gt "$(sed '/^$/d' /tmp/size.out|wc -l|tr -d ' ')" 0 "-play size count"
"$ROOT/bin/-sync" -f -j 0 "$LIB" >/tmp/sync.out 2>"$TMP/sync.err"; [[ -f "$SYNC_DIR/meta" ]] && ok "-sync creates meta" || bad "missing meta"; grep -q 'sync: stat' "$TMP/sync.err" && ok "-sync per-file logs" || bad "sync logs"; assert_eq 6 "$(awk -F '\t' 'NR>1 && $15==0{c++} END{print c+0}' "$SYNC_DIR/meta")" "-sync active count"
"$ROOT/bin/-play" -v "$LIB" -F -H -d 2 -M --shuffle --fs >/tmp/mpv.out 2>"$TMP/mpv.err"; grep -q -- '--shuffle' "$MPV_LOG" && grep -q -- '--fs' "$MPV_LOG" && ok "-play mpv args" || bad "mpv args"
log "ALL OK ($pass checks)"
