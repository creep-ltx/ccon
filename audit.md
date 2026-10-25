# CCON source audit — 1.2.6b3 (audit5, the consolidated document)

Full read of `ccon-handler.e` at `$VER: ccon-handler 1.2.6b3 (27.7.26)`
(8405 lines, HEAD @ baead1e), delta-focused on the ~490 lines gained
since audit4's 1.2.5b1 baseline: the 1.2.5b2 audit-fix batch, the
b3–b8 "evening of Ed" ladder, and the three 1.2.6 features (iconify
gadget, complement cursor, drag and drop). Read-only: nothing in this
pass has been changed.

**This document replaces `audit.md`, `audit2.md`, `audit3.md`,
`audit4.md` and the three roadmap files** (his call, 28.7.26). The
retired texts remain in git history (`git log --all -- ccon/audit*.md`);
the changelog carries the release-level story of every fix that
shipped. What this document keeps from them is the part that must stay
live: **the ledger** — the current, code-verified status of every
prior finding ID — at the bottom. The ledger pass re-checked all 44
prior IDs against the current source; one materially stale row was
found and corrected there (old B8).

Method: four parallel read passes (the 1.2.6 features; the 1.2.5b2–b8
fixes incl. verification that audit4's D1–D3 landed as prescribed; the
whole-file cross-cutting sweeps; the ledger fact-check), then every
ranked finding re-verified against the cited lines before it was
written down.

Numbering is a fresh series (**A1..**) — B/P/H, C, D and E are taken
(audits 1–4 and the 1.2.4 render campaign).

**Status update (28.7.26): A1, A2, A7 and A8 are FIXED and
boot-verified in 1.2.6b4** — full findings in todo.md's 1.2.6b4
section, fix shapes in audit-roadmap.md Batch A. A1's fix clears the
1.2.6 release blocker. A2 was proven live by `tests/ccinfo0`
(res2=115 ERROR_BAD_NUMBER from a CCON: shell; res2=205 from stock
CON: = sender-routing, the negative control). **A3 and X1 are FIXED
and boot-verified in 1.2.6b5** (the `acceptreset()` factoring; the
A3 repro healed on the glass, conbench A/B b4-vs-b5 identical).
**A4 in 1.2.6b6, A5+A6 in 1.2.6b7, and A9+A10+A11 (both arms) +
X2–X5 in 1.2.6b8 — all boot-verified 28.7.26. THIS AUDIT IS
CLOSED: every finding fixed or written down, five batches
boot-green in one day (b4–b8).** The campaign itself was then
audited before release — **Audit6, the after-fixes pass, at the
bottom of this document** (fresh F-series vs 1.2.6b8 @380f8ec):
one narrow pre-existing accounting hole (F1) and four comment
repairs shipped as **1.2.6b9, boot-verified 28.7.26** — F4/F5 are
recorded behaviour. **Audit6 is closed.** The 1.2.6 release ladder
is what remains.

---

## Verdict

The b5–b8 Ed machinery is the strongest work in the delta: the
three-way close protocol covers its client shapes exactly, `alteat` is
render-scoped by construction despite being a global, and the
altpop/altrestore split honors the plane-mask invariant in both
directions. The audit4 fixes (D1–D3) all landed **exactly as
prescribed**, ELSE-arms and warnings included. The choke-point flush
discipline audit4 declared complete **still holds** across all three
new features — every path that observes the model or the glass
flushes first, with one argued-sound, undocumented exception (X2).

What broke is what always breaks here: the seams. b1's six lines
re-broke the oldest rule in the drain loop — with the rule's own
comment four lines below the new call (A1). The drop path re-ran most
of the house checklist impressively (lock hygiene, buffer caps,
nested-IF pointer discipline, no-DOS purity) and then skipped the two
guards that live in its own siblings (A3, A7). And audit4's X3
prediction — "the un-factored accept-reset list is how the next
D-item gets written" — came true verbatim: the third copy is missing
three of its five entries (A3).

| Severity | Count | Items |
|---|---|---|
| Crash / wild write | 2 | A1 (new in b1), A2 (pre-existing) |
| Corruption (wrong state/text) | 2 | A3, A4 |
| Corruption, narrow trigger | 1 | A6 |
| Cosmetic | 2 | A5, A10 |
| Hygiene | 4 | A7, A8, A9, A11 |
| Maintenance / comments | 5 | X1..X5 |
| Performance | carried | P-notes (all prior, none new) |

---

## Correctness

### A1 — the iconify gadget closes the window whose UserPort the drain loop is still reading

**Where:** main() 905–918 (dispatch), 882 (the re-fetch), 919–922 (the
invariant, stated); `doiconify()` 2493 → `hidewin()` 2540–2542.

```e
915              IF code = 1 THEN doiconify() ELSE doclosew()
...
918        UNTIL im = NIL
919        IF c.closereq             -> deferred: never CloseWindow while
920          c.closereq := FALSE     -> draining the port it owns
```

`doiconify()` on the Code=1 branch runs `hidewin()` →
`CloseWindow(curcon.win); curcon.win := NIL` synchronously, mid-drain
of that window's own UserPort. The message just dispatched was
non-NIL, so `UNTIL im = NIL` loops back to
`im := GetMsg(c.win.userport)` at 882 with `c.win = NIL` — a load
from absolute address $56 (win_UserPort off a NIL base). Whatever
lives there is treated as a MsgPort; a garbage non-NIL GetMsg return
then feeds `ReplyMsg(im)` a wild pointer, which **writes** through it.

This is the exact violation the `closereq` machinery four lines below
exists to prevent, and the true-close branch (`doclosew`, Code 0)
honors it. The old RAMIGA+I path is safe — it calls `doiconify()`
from `ihkey`, outside the window-port drain. The b1 boot pass ("It
works, of course it does") means address $56's contents happened to
parse as an idle port on that machine — luck, not soundness; a
different ROM/MapROM/RTG layout can detonate it.

**Reachable:** every click of the new gadget — the feature's only
trigger.

**Fix:** the house pattern, one flag: in the drain,
`IF code = 1 THEN c.iconreq := TRUE ELSE doclosew()`; beside the
closereq check after `UNTIL im = NIL`:
`IF c.iconreq THEN (c.iconreq := FALSE; curcon := c; doiconify())`.
New console field — `New()` zeroes it, no init needed. RAMIGA+I keeps
its direct call.

---

### A2 — `ACTION_DISK_INFO` zeroes 36 bytes through an unvalidated client BPTR: `arg1 = 0` wipes low memory

**Where:** `dopkt` 1522–1526.

```e
    id := Shl(pkt.arg1, 2)      -> BPTR to InfoData
    zp := id
    FOR i := 0 TO 8
      zp[i] := 0
```

`arg1` is the only packet argument in the dispatch that is *written
through* with no validation. A client passing NIL (a failed
allocation it never checked) makes `id = 0` and the loop zeroes
addresses 0–35 — including ExecBase's pointer at 4 — before
`disktype`/`volumenode` land there too. Pre-existing (1.2.1-era, not
a regression), same class as audit4's D1: READ/WRITE buffer trust is
inherent to the protocol and shared with stock handlers, but this is
the one case where **we** proactively write through a client pointer,
and it is one line to guard.

**Reachable:** any buggy client calling Info() on a console with a
NIL InfoData. Not reachable from correct DOS calls.

**Fix:** before the Shl:
`IF pkt.arg1 = 0 THEN (ReplyPkt(pkt, DOSFALSE, ERROR_BAD_NUMBER); RETURN)`.

---

### A3 — `dodrop()` skips the accept-time reset trio: the audit4-X3 prediction, come true

**Where:** `dodrop()` 2338–2353; the pattern it misses: `dowrite`
1614–1617, `swaccept` 1748–1751, `ihkey` 7389–7391.

A drop is "input, same manners as a keystroke" (its own comment), but
between `flushout` and the insert it runs only `snaplive()` — not the
`IF curcon.sbsrch THEN sbexit()` / `clearsel()` / `tcclose()` trio
that both accept siblings carry (the audit3-C9 fix relocated exactly
there because `snaplive()` deliberately does not do it itself — the
1610 comment says every caller must). Three consequences:

1. **Ctrl+R scrollback-search active** (`sbsrch`): the drop
   pasteinserts into the *match* line while the user's real line sits
   stashed; `sbsrch` stays TRUE, so the next keystroke feeds the
   search fragment (`sbadd` → `sbfind` yanks the view to a stale
   match) and Esc restores the stash — **the dropped path silently
   vanishes**. Audit3 C9's exact shape, reintroduced on the newest
   input path (third sighting of this species).
2. **Completion menu open** (`tcactive`): the path inserts under the
   frozen menu; `tcreplace`'s spans are stale and the next Enter is
   eaten by the menu-close guard instead of committing.
3. **Standing highlight:** output kills it, keys kill it, a drop
   leaves it standing. Cosmetic.

**Reachable:** (1) is four user actions, no client needed.

**Fix:** mirror 1614–1617 after the win-NIL guard — or do X1 below
properly and give all three sites the one `acceptreset()` this file
now owes twice over.

---

### A4 — `lockpath()` cannot tell a failed parent hop from the root: a wrong path is inserted, not nothing

**Where:** `lockpath()` 2456, 2462; `fscall()` 7522–7524; the
contradicted contract at 2428–2430.

```e
2456        par := fscall(fl.task, ACTION_PARENT, cur, 0, 0)
...
2462    cur := par                  -> par = 0 on the root: the walk ends
```

`fscall` returns only `res1`; ACTION_PARENT's failure (res1=0, reason
in the discarded res2) is indistinguishable from reaching the root
(also 0). A mid-walk failure ends the walk early with `ok` still
TRUE, and the emit loop crowns the last-collected *directory* segment
with `":"` — `sub:file` instead of `DH0:Work/sub/file`, inserted at
the cursor as if typed. The block comment promises the opposite:
"FALSE = a hop failed … insert nothing rather than something wrong" —
the guard exists for EXAMINE failure (2458–2459) and overflow
(2448–2449), but not for the one call whose failure hides inside its
success value.

**Reachable:** ACTION_PARENT allocates a lock; under the classic 68k
memory squeeze or an FS hiccup it fails with res2=ERROR_NO_FREE_STORE.
Rare — but the failure mode is silent wrong text on a command line,
plausibly executed against the wrong file.

**Fix:** an `fscall2(..., res2ptr)` variant that reads
`fspkt.pkt.res2` after the wait; treat `(par = 0) AND (res2 <> 0)` as
`ok := FALSE`. One extra check at one call site.

---

### A5 — `doresize()`'s `clearsel()` repaints at the OLD grid into the already-resized window

**Where:** `doresize()` 3374 (before `gridcalc()` at 3391) →
`clearsel()` → `selrepaint()` (rmax clamped to the OLD `rows - 1`) →
`drawselrow()` (paints all OLD `cols`).

The b8 lesson — old-grid paint overdraws the resized window's border,
and the layer covers border pixels — is documented on **both
neighbors** of this call: `altpop()` three lines above ("the paint
half runs at the OLD grid and overdrew the resized window's border")
and `dropeditmirror()` below ("its PAINT ran at the old geometry into
the already-shrunk window, wiping the sizing gadget"). `clearsel()`
between them still repaints every selection row full-width at old
coordinates when a standing highlight dies with the resize. The final
heal RectFills only the inner region — border pixels stay overpainted
until Intuition redraws the frame. With `wasalt` there is a second
facet (the repaint shows restored transcript under the client's alt
page) but the full repaint below heals that one immediately.

**Reachable:** any window with a standing highlight, shrink it. Also
during a More session (More holds no event mask, so drag-select works
mid-page).

**Fix:** replace the call with a state-only clear
(`curcon.sello := -1; curcon.selhi := -1`) — the full repaint below
owes the pixels anyway, the same reasoning b8 applied to `altpop()`.
`clearsel()` itself stays for its other callers.

---

### A6 — the mid-resize re-snapshot captures the edit-line mirror for a cooked alt-screen client

**Where:** `doresize()` 3493–3506: `drawedit()` (3496) runs before
`altsave()` (3499); contrast the `?47h`-time snapshot, which runs
inside the render bracket after `eraseedit()`.

For a **cooked** client holding the alternate screen, `drawedit()`
mirrors the edit line's cells into the model and `altsave()` then
snapshots those rows — so the eventual `?47l` restores the edit line
as phantom transcript text, in the model, archived into scrollback.
A miniature of the exact wound class b7 closed ("nothing of the
client's page ever touches the ring" — here it is our own editor's
page). Raw clients — More and Ed, the only real alt-screen users —
are unaffected (`cursdraw` is pixels-only), which is why nothing has
been seen. Found independently by two passes.

**Reachable:** only a cooked client that sends `?47h`, then a resize,
then `?47l`. No shipped client does this today; the invariant is
stated absolutely, so it is a finding, not a note.

**Fix:** hoist the `IF wasalt THEN altsave()` block above the
raw/cooked paint block (raw indifferent, cooked snapshots a clean
model). Do **not** merely reorder drawedit after altsave inside the
cooked arm — `drawedit`'s `edroom` can scroll and desync `altsbtop`.

---

### A7 — the drop path uses the fs plumbing without `dotab`'s NIL wall

**Where:** `dodrop()`/`droppath()`/`lockpath()` (all via `fscall`);
the guard the sibling carries: `dotab()` 8264–8265
(`IF (fsport = NIL) OR (fspkt = NIL) OR (fsfib = NIL) OR (fsname = NIL) … RETURN`).

If `fspkt`/`fsfib`/`fsname` failed to allocate at mount (main()
tolerates it), a drop writes packet fields through NIL — or hands the
target filesystem a zero FIB BPTR, making **it** write 260 bytes at
address 0. Near-theoretical (alloc failure at mount + a drop), but
the one-word-asymmetry class again: the guard exists ten screens away
in the exact sibling. (`loadhistfile`/`savehistfile` share this
pre-existing exposure; noted.)

**Fix:** `dotab`'s guard line at the top of `dodrop()`.

---

### A8 — `curfill()` clobbers a borrowed rastport's AreaPtrn

**Where:** `curfill()` 3864–3872.

`om := drawmode` is saved and restored; `areaptrn`/`areaptsz` are
unconditionally forced to NIL/0 — even when the ghost pattern was
never installed, and even on a **borrowed** CTerm frame, where winact
ghosting explicitly applies and any pattern the owner keeps on its
own rastport is silently destroyed by every cursor paint. Owned
windows: harmless.

**Fix:** save/restore both fields beside `om` — the three-line shape
the drawmode already uses.

---

### A9 — a full input queue eats a requested close-gadget click whole

**Where:** `doclosew()` 3540–3550 → `ihreport()` 7472 (room check
fails → silent RETURN).

For the Ed path the click's only effect is the queued class-11
report; with `inq` full (wedged client, ~2 KB backlog) the report is
dropped and there is no fallback — no report, no EOF, no closereq.
Stock discards *unrequested* clicks; this discards a **requested**
one. Narrow (a wedged client wasn't going to run its quit flow
anyway) and retryable once the queue drains.

**Fix (if wanted):** `DisplayBeep(NIL)` when the room check fails on
this path (the C5 audibility rule), or a one-slot pending flag
replayed from `inputarrived()`.

---

### A10 — `alteat` survives non-printable output: FF/TAB then a working LF loses that LF

**Where:** armed 5146; cleared at 5560 (printables), 5779 (the eaten
LF), 5842 (render exit) — but not by FF (5795), TAB spaces, or CSI
motion.

A hypothetical alt-screen client whose exit packet is
`?47l · FF · LF` (or TAB then LF) loses a newline doing real work.
Ed's proven packet (`?47l ESC8 \n`) and More's (nothing after
`?47l`) are unaffected. Render-scoped by construction, so the
exposure is strictly in-packet.

**Fix:** clear `alteat` in the FF and TAB branches ("any output
disarms"); leave CSI motion armed — that is ESC8's own family, and
disarming there defeats the feature.

---

### A11 — multi-icon drops are whole-or-nothing per *icon*, not per drop; cooked overflow is silent

**Where:** `droppath()` 2412–2417 (raw: per-path `inqroom` + beep in
`dodrop`'s FOR loop); `pasteinsert()` 4407 (cooked: per-char
`IF l < cap`, no else).

A 5-icon drop into a nearly-full raw queue can deliver icons 1, 2, 3,
5 — one beep, a silently incomplete *and reordered-by-omission*
argument list. The todo spec's "a drop that does not fit beeps
instead of half-arriving" treats the drop as the unit. Cooked side:
characters past `edcap` drop with no signal at all. Both need a
genuinely full queue / very long paths, hence hygiene.

**Fix:** resolve all paths first, test room once, beep-and-abort the
whole drop; cooked: beep when any character was refused.

---

## Maintenance (X) and performance (P)

- **X1 — `acceptreset()` is now owed three times.** audit4's X3
  (factor the accept-time reset list shared by `dowrite`/`swaccept`)
  was not done; b3 wrote the third copy and lost three entries in the
  copying (A3). The two old sites are verified in sync today —
  line-for-line — but the prediction has now come true once. Factor
  it while A3 has the sites open.
- **X2 — `doactive()` is the one glass-touching event path with no
  pre-flush, and the argument for why that is sound is written
  nowhere.** It holds only because model and glass lag *together*
  under accept-then-render and redress reads values the pending bytes
  cannot have moved (`reanchor` runs only inside `dorender`). If a
  future change lets `wob` bytes move `cx/cy/ancx/ancy` before
  render, this becomes a live desync site with no warning comment.
  Either add the (cheap) `flushout` for uniformity or write the
  two-line coherence argument down. Found by two passes
  independently.
- **X3 — audit4 X2 still owed:** `flushout()`'s win=NIL discard arm
  still lacks its "unreachable by construction; kept as a net"
  comment (byte-identical to the 1.2.5b1 baseline).
- **X4 — the b7 reflow's correctness depends on `altpop()` succeeding
  whenever `altvalid`** (a FALSE return there would archive the
  client's page — the exact b7 wound). Unreachable today; one
  sentence at the `altdrop()` belt would keep it that way.
- **X5 — stack headroom note:** `droppath` + `lockpath` add ~2.0 KB
  of frames (pb 620 + tb 560; segb 400 + sgo/sgl 192 + nb 110) on
  E's 10000-byte runtime stack. Fits with room; remember it the next
  time a buffer joins this call chain.

- **P — the parked `fscall` timeout (old audit2 P6) got its third
  caller family and its most casual trigger yet.** Tab/Enter/first
  open could always hang every CCON window on a wedged filesystem;
  drag and drop now does it with a mouse gesture, up to 3+hops calls
  per icon. Both feature passes flagged the escalation. Still his
  call — but the re-decide note this ledger carries (below) now has
  a stronger case than when audit3 wrote it.
- **P — carried, all confirmed still accurate at 1.2.6b3:**
  `scrollview()` full-redraw + `settitle()` per wheel tick (audit3
  P1 — still the largest interactive cost on 68k); `histpersist`
  blocks the process per Enter (audit3 P3, parked design trade);
  reflow doubles peak model memory (audit3 P4); audit4's P1–P3
  render notes (WAIT_CHAR pollers forfeit aggregation; `vblankscan`
  worst-case-on-blank; `dffull` RectFills a blank screen). None
  worth code until a client or a benchmark row says otherwise.

---

## Verified sound

The load-bearing re-verifications, condensed from all four passes:

- **The audit4 fixes landed exactly as prescribed.** D1: negative-len
  guard at `dowrite` 1602–1605 (reply -1/ERROR_BAD_NUMBER, parity
  with `swaccept` 1744, packet still replied; a negative-len write
  stashed by `swaccept` re-dispatches into the same reply). D2:
  `vbrecheck()` 4628–4631 carries the prescribed line *including the
  ELSE arm* for LINES=0 consoles, called at all three prescribed
  seams (`pastehintroom` 4519, `edroom` 5881, dotab menu loop 8334);
  the warning was heeded — `drawedit()` contains no vblank write; an
  exhaustive `screenscroll()` caller sweep found no new unguarded
  site. D3: `dfd[tmp] := 0` at 683 in the canonical init loop.
- **The choke-point discipline holds at 1.2.6b3.** Every
  model/glass-observing path flushes first — checked each: END 1388,
  READ 1430, WAIT_CHAR 1452, SCREEN_MODE 1475, dowrite's sync/join
  paths, conclose 1265, doiconify 2490, doresize 3346, doclosew 3537
  (the class-11 report included), selmouse 4123, dopaste 4281,
  dovanilla 6756, dorawkey 7063, dodrop 2341. `flushwq()` on every
  drag-death path: release, resize, closewin (windowed and
  windowless), the lost-button-up belt; iconify mid-drag legally
  re-parks and replays. The one no-flush exception is argued sound
  and is X2.
- **All 15 SELECT packet cases reply on all branches** — checked
  each, including every error arm, park-and-reply-later path
  (satisfyreads/satisfywaits/timer/closewin) and the DIE/default
  arms. `fh_Arg1` conok-validated on END/READ/WRITE and in swaccept;
  every non-packet entry (UserPort walk with next-taken-first, ring
  drain with conclose scrub, timer, sweepstash re-entry, AppMessages)
  resolves its console against the live list before trust. The one
  write-through-unvalidated-arg1 exception is A2.
- **Resource lifecycle clean.** New acquires: `gpat` (chip)
  freed in killhandler — the one allocation E's exit doesn't track,
  correctly hand-freed; `appwin` removed strictly before its window
  dies on all three exits (hidewin 2536–2539, closewin 3079–3082,
  DIE-implies-empty-list); AppIcon and AppWindow never coexist. Old
  ladders re-verified at the new version: openwin failure unwind,
  reopenwin stride-mismatch drop, reflow all-four-or-none, alt-plane
  idempotent drops, pens symmetric across hide/reopen/close,
  abort-before-delete on the timer clone. `lockpath` frees every
  intermediate lock on every arm including both failure exits; the
  drop's argument locks are correctly left to Workbench, resolved
  before the unconditional ReplyMsg.
- **The no-DOS rule survived its riskiest feature yet.** Drag-and-
  drop path resolution is pure hand-rolled packets on the private
  fsport — no NameFromLock, no Lock, no GetDiskObject anywhere in
  the delta; AddAppWindowA/RemoveAppWindow/AddAppIconA are
  workbench.library list-ops, not packet senders; `fscall` still
  refuses our own port (closing the self-drop deadlock).
- **The complement cursor's XOR discipline is airtight.** The one
  non-idempotent primitive has exactly two callers, both protected:
  `cursdraw` self-erases first; `drawedit`'s blip paints full-depth
  JAM2 Text over the cell before every fill. Erase is
  repaint-from-model — idempotent by construction, the right erase
  for an XOR mark. `curfill` runs only outside the masked bracket
  (render restores mask $FF before any caller), and both fills are
  erased full-depth before the next masked render. `winact` is
  ground-truthed from WFLG_WINDOWACTIVE at both open sites, kept
  current by always-on frame classes; `doactive`'s three guards
  (same-state, win-NIL, viewoff) each hold. `gpat` is
  NIL-survivable at its one read site.
- **The b5–b8 Ed machinery is internally consistent.** The stale-
  evmask hazard is closed twice over (SCREEN_MODE 0 clears the whole
  mask — the comment even names Ed's missing CSI }; closewin clears
  it too). `alteat` cannot cross a packet, a console, or an event
  (armed only in-render, killed at render exit; the residual
  in-packet case is A10). The altpop/altsave ordering around
  gridcalc is right (dims compared old-to-old, reflow reads real
  transcript); altsave-at-new-geometry fails soft to the pre-b11
  behavior; the class-12 report is sent after re-arm, so Ed's
  repaint lands on the re-armed session; a non-subscribing client
  degrades exactly as the doc claims.
- **The E-trap sweep on the delta came back clean.** Every new
  global DEF-initialized or covered by New()-zeroing + coninit; every
  new AND/OR site evaluates only safe operands (the C3 nested-IF
  discipline extended to the new AppMessage drop branch); no new
  client-derived CopyMem length; no new Mod/DIVU on unbounded
  values; every drop-path buffer cap checked before its write
  (lockpath's 398/24/cap chain, droppath's 548/558/620 chain,
  tcbstr/tcfibname clamps covering both BSTR and C-string FIBs).
- **Drop-while-X surfaces covered by construction:** scrolled-back →
  snaplive precedes the insert; iconified → win-NIL guard (the
  AppWindow doesn't exist then anyway); mid-resize → window ports
  drain before wbport in the same wake; raw client → whole-path
  inqroom + one inputarrived; wa_Lock=0 left-outs skipped;
  drawer/volume drops emit `Vol:dir/` and `Vol:` per spec. Borrowed
  frames never register an AppWindow (the "CTerm: no drop target"
  todo row is real) — and a borrowed frame's iconify gadget, if its
  owner tagged one, is deliberately swallowed by the fwin guard.

---

## The ledger — every prior finding ID, verified against 1.2.6b3

Status re-checked in the source (not just the docs) by the ledger
pass, 28.7.26. "Fixed" rows were confirmed present; only deltas from
the old docs' claims are annotated.

**audit1 (1.2b1 pass):** B1 eraseedit theft ✓fixed b6 · B2 resize
grow ✓b7 · B3 CSI truncation ✓b8 · B4 AUTO retry ✓b7 · B5 ACTION_DIE
✓b13 · B6 conbysender ✓b12 · B7 width reflow ✓b10a ·
**B8 raw-resize — the doc said OPEN; it is FIXED** (1.2b25 @
1c989df: the always-drain with `parked` suppressing only input
classes; the 1.2b15 "fix reverted" breakage was the ESC[ arrow-key
bug, misattributed; hardened for mid-alt resize in 1.2.5b7/b8;
audit1's "Ed does not use ?47h" premise was disproven by the b6
EDDBG telemetry — Ed brackets its session with the alt screen) ·
P1 curattr ✓ · P2 Mod/Div ✓ · P3 history walk ✓b16 · P4 curcon
hoist ✓ · P5 hist rewrite ✓b11 · H1–H5 ✓ (H4 resolved-as-comment,
by design).

**audit2 (1.2b14 pass):** B9 textattr leak ✓b15 · B10 selcopy LF
✓b17 · B11 paste spin ✓b17 (subsumed by C4) · B12 runaway freeze
✓closed, was ls, not CCON · P6 fscall timeout — **still parked**
(comment present at 7495–7509, WaitPort 7522 timeout-less; see the
P-note above: exposure widened by dnd, re-decide requested) · H3
condispose planes ✓b15 · H6 stray bytes ✓.

**audit3 (1.2 pass):** C1 sbmax floor ✓1.2.1 (both directions) · C2
iconify geometry ✓ (+sbcols belt) · C3 doappmsg conok ✓ (discipline
extended to the 1.2.6b3 drop branch) · C4 chunk overflow ✓ · C5 raw
paste ceiling — partial by design (beep ships, tail-pump never
built; documented) · C6 iconified wq accept+discard — deliberate,
his call stands (1580) · C7 diskfont close ✓ · C8 icon-less strand
✓ · C9 snaplive/sbsrch ✓ (relocated to the accept sites — and A3 is
its third-sighting echo) · C10 edcap ✓ · P1 scrollview wheel —
**still open** (4679–4693), the big interactive perf item · P2 ✓ ·
P3 histpersist — parked · P4 reflow peak — parked · X1 ✓ · X2
wrap-idiom unification — not done (mitigated by C1's floor) · X3 tf
comment — not done · X4 SGR-cap doc note — not done · X5 255-col
doc ✓ (plus LINES + paste-limit wording).

**audit4 (1.2.5b1 pass):** D1/D2/D3 ✓ fixed 1.2.5b2 exactly as
prescribed (verified in detail above) · P1/P2/P3 — accurate,
unactioned by intent · X1 WODEFER arm — deliberate, unchanged · X2
flushout comment — **not done** (now this doc's X3) · X3
acceptwrite factoring — **not done, and its prediction came true**
(now this doc's X1/A3).

**Genuinely open at 1.2.6b3, the whole list:** A1–A11 above; X1–X5;
audit3 P1 (wheel redraw), audit2 P6 (fscall timeout, parked), audit3
P3 (histpersist, parked), audit3 P4 (reflow peak, parked), audit3 C5
tail-pump (never built, documented), audit3 C6 (deliberate), audit3
X2/X3/X4 (hygiene/doc debt), audit4 P1–P3 (notes).

---

## Great / Good / Meh / Bad / Terrible

### Great

- **The b6 EDDBG habit paid for the whole ledger.** Capturing Ed's
  actual exit bytes settled `alteat`'s design, disproved audit1's
  B8 premise, and turned "fix reverted, cause unknown" into "the
  arrow-key bug, misattributed" — the read-what-the-client-sends
  discipline keeps outranking every hypothesis.
- **`alteat` is a global that provably cannot leak.** Armed only
  inside render, killed unconditionally at render exit — scope by
  construction where the language offers none. The right way to do
  a one-shot in E.
- **The drop path's packet plumbing.** Hand-rolled ACTION_PARENT
  walks with per-arm lock hygiene, whole-or-nothing segment
  buffers, and BSTR/C-string FIB tolerance — the no-DOS rule held
  through the feature most likely to break it.
- **The XOR cursor shipped with its hazard already understood** —
  "repaint is idempotent, a second XOR is not" was written before
  the code, and the two-caller discipline enforces it.

### Good

- The three-way close protocol's client-shape coverage, including
  the stale-evmask double-close (SCREEN_MODE + closewin).
- The altpop/altrestore split and the b8 border lesson applied at
  the site that taught it.
- D1–D3 landing letter-perfect, ELSE-arms included — prescriptions
  are being read, not skimmed.

### Meh

- The accept-reset list existing three times (X1). Twice was
  "fragile by construction"; three times with a divergent copy is a
  bug factory in production.
- `doactive`'s soundness argument living in no comment (X2).

### Bad

- **A1** — six lines, and one of them re-broke the drain loop's
  oldest rule with the rule's own comment four lines away. Audit3
  said it about the first iconify, audit4 said it about the accept
  path, and it is still true: *new seams must re-run the old
  checklist* — especially the six-line features, because nobody
  audits six lines.
- **A4** — a contract stated in the block comment ("insert nothing
  rather than something wrong") and honored on two of three failure
  arms. The third arm's failure is invisible in res1, which is
  precisely why it needed the comment's promise kept.

### Terrible

Nothing. Four audits and a consolidation in, the file's failure
species has never changed: seams, not confusion. The invariants are
real, the instruments exist, and every crash-class find in this
pass is one flag or one line from closed.

---

## Suggested order

1. **A1** — one flag + two lines, crash-class, the release blocker
   for 1.2.6.
2. **A3 + X1 together** — factor `acceptreset()`, call it from all
   three sites; closes the corruption and retires the prediction.
3. **A2** — one line.
4. **A4** — `fscall2` + one check.
5. **A7** — one guard line, while the drop file is open.
6. **A5** — swap a call for two assignments.
7. **A6** — hoist `altsave` above the paint block.
8. **A8–A11, X2–X5** — the hygiene sweep, one sitting.
9. The P-notes stay notes — except the fscall-timeout re-decide,
   which now has three trigger families and deserves its sentence
   in todo.md.

---

# Audit6 — the after-fixes pass (28.7.26, vs 1.2.6b8 @380f8ec)

The audit5 fix campaign (b4–b8, five batches, one day) audited before
it ships — the same discipline every prior campaign got. Method:
two independent review passes run in parallel (an adversarial
fix-verifier working item-by-item against audit5's prescriptions,
and an exhaustive caller-sweeper over every proc the campaign
touched: pasteinsert's new return, fscall's delegation — all 25
sites — acceptreset's four constituents from three contexts,
alteat's new clears against Ed's real exit packet, iconreq's
lifecycle, altsave's moved call), plus an author pass focused on b4
(written by a session that died before its code was ever re-read).
Every finding below re-verified against the cited lines before it
was written down. Fresh series: **F1..F7**.

## Findings

### F1 — cooked scrolls while a snapshot is armed were never counted: `rawscr` is fed only under `rawmode`

**Where:** `screenscroll()` 4940, `dfscroll()` 5013; the accounting
they starve: `altpop()`/`altrestore()`'s `over` computation (4871).

`altpop()`'s content restore is index-self-consistent (the saved
rows are copied back at the restored `sbtop`), so `rawscr` guards
exactly one thing: the ring-WRAP overflow — scrolls during an alt
session that recycled ring rows far enough to eat the oldest
history, which must shrink `sbcnt` on restore. Both scroll sites
count only `IF rawmode`. A **cooked** client holding the alt screen
(none shipped — More and Ed are raw; the same hypothetical as A6)
scrolls via `drawedit`→`edroom`→`screenscroll` on every spilling
edit line, uncounted — `over` understated, `sbcnt` restored too
high, and the oldest history row after `?47l` is a recycled row
shown as a wrong join. **Pre-existing since the alt machinery** (any
in-session keystroke scroll had the hole); the b8 A6 hoist added one
more instance (the doresize `drawedit` now follows the re-snapshot)
and the review of that hoist is what surfaced it. Same
reachability tier as A6: no shipped client. **Fix (b9): count the
scroll whenever `altvalid`, not only under `rawmode` — one line at
each site, closing every instance at once (keystrokes and resize
alike).**

### F2 — the X2 comment's parenthetical is false as written

`doactive()`'s new coherence comment says "reanchor runs inside
dorender only" — `reanchor()` also runs at the SCREEN_MODE
cooked-revert (1504) and the Return commit (6992). Both flush
first, so the safety ARGUMENT stands; the stated reason doesn't,
and a wrong written-down reason is how the next edit goes wrong.
**Fix (b9): reword — pending wob bytes move the anchor only through
dorender; every other mover flushes first.**

### F3 — the X5 stack sentence names the wrong deepest path

The mountlist comment claims drop resolution
(dodrop/dropbuild/lockpath, ~2.1 KB) is the deepest handler path.
The history-save chain is deeper: `savehistfile` carries
`buf[2048]` and calls `tcresolve` (`dcopy[300]` + `devname[40]`) ≈
2.5 KB, reached from dovanilla→histpersist and conclose. Headroom
conclusion (10000-byte E stack) unaffected. **Fix (b9): correct the
sentence.**

### F4 — a drop larger than the queue is refused forever, and the write-up doesn't say so (NOTE, kept)

A11's whole-drop check refuses `total > INQMAX-1` (2047) even
against an EMPTY queue — the beep suggests "retry when it drains"
but no drain can ever make it fit; the old per-icon code delivered
what fit. This is whole-or-nothing semantics taken to its honest
edge (delivering a silently truncated argument LIST is the exact
A11 wound), so the behaviour stands — **fix (b9): one comment line
at the check acknowledging the edge.** A future escape hatch, if
ever wanted, is per-icon delivery when a single drop can never fit.

### F5 — the total=0 early return skips the old incidental eofpend wake (NOTE, accepted)

A fully-failed raw drop used to still call `inputarrived()`, which
could incidentally serve a standing `eofpend` to a queued reader;
the A11 early return skips that. Arguably more correct (a failed
drop performing an unrelated EOF delivery was an accident), zero
shipped-client impact. Recorded, no change.

### F6 — a line-number comment went stale the same day it was written

The b6 lockpath comment cites "the 2463 promise"; b8's edits moved
the promise header to ~2493. Line numbers belong in audit documents
(dated, versioned), not in code comments. **Fix (b9): reword to
name the header, not the line.**

### F7 — the A7 wall's comment still says `droppath`

`dodrop()`'s guard comment names a proc b8 renamed to `dropbuild`.
**Fix (b9): rename in the comment.**

## Verified clean

A1 (New-zeroed iconreq, per-console drain, clear-before-act,
iconreq-then-closereq cannot double-CloseWindow — closewin removes
the AppIcon first and replies every parked packet on the windowless
arm; ihkey's direct call runs in ihdrain before the window walk) ·
A2 (guard placement, DOSFALSE + ERROR_BAD_NUMBER) · A7 (all four
globals, before any use) · A8 (single exit, restore on it) · A3+X1
(all four constituents curcon-pure from all three contexts;
breaktask stays packet-side; tcclose mid-swaccept repaints a
settled model — the packet's bytes are not yet in wob) · A4 (all 24
fscall sites 5-arg; no caller reads fspkt.res2 after return; {r2}
legal on a stack local; strictly sequential fspkt use incl. the A11
double resolve; locks freed on every arm) · A5 (clearsel's only
state was sello/selhi; the XOR cursor's pixels die under the
unconditional inner RectFill; stale selvo gated by sello=-1) · A6
(landed as prescribed, ?47h-shape preconditions matched — F1 is the
surviving edge, pre-existing) · A9 (IECLASS_CLOSEWINDOW is
doclosew's exact class; ihreport runs only in the handler task, so
DisplayBeep is legal) · A10 (TAB clear first-in-branch, FF clear
covers both dfon arms, ESC8's bytes cannot reach either — cesc
routing verified byte-by-byte) · A11 (pb/tb bounds proven, 563 max
against 620; per-icon belt makes partial arguments impossible under
any dropbuild return; pasteinsert's flag only counts cap-refused
printables; dopaste legally discards the new return) · X3 (the
discard arm IS unreachable: every hide path flushes first) · X4
(altvalid implies a current-grid snapshot, altpop's grid check
cannot fail at doresize entry) · plus the general pass: no new
Mod/DIVS hazards, E-VO one-liner forms valid, $VER bumped.

## Verdict

The campaign held: eleven fixes and five comment items, and the
worst thing the after-pass found is a pre-existing accounting hole
in the same no-shipped-client corner the fix it reviewed was
hardening (F1), plus four comment corrections — two of them in
comments this very campaign wrote (F2, F6): documentation written
at speed rots at speed. F1's one-line-per-site fix and the comment
repairs ship as **1.2.6b9**; F4/F5 are recorded behaviour, kept.

---

# Audit7 — the 1.2.7 config campaign (11.8.26, vs 1.2.7b15 @2317ddd)

An author pass over b4–b15: the palette work (b4–b7), the config
file and its keys (b8–b9), device completion (b10), the resize
repaint fix (b11), the menu's arrow walk and Esc-abort (b12–b13),
the grounding directives and TITLE= (b14), and ICON= (b15).

Every finding below was traced in the source and, where it is a
defect, fixed and proven — F1 in the harness, F2 by inspection —
shipped as **1.2.7b16**.

## Findings

**F1 — a grounding directive at field 4 lost the title AND grounded
nothing.** *(defect, b14 regression, fixed)*

b14 matches `DEFAULTS` and `CONFIG` in `parseopt` deliberately: the
f=0 shortcut only switches a spec to options-only when the first
field names a real option, so without a match `CCON:DEFAULTS/LINES384`
would read `LINES384` as a window Y. But `parsecon`'s field 4 uses
that same return the other way round — `IF parseopt(tok) = FALSE THEN
StrCopy(wtitlebase, torig)` — so a *matched* token is not a title.

And the pre-scan deliberately skips fields 1–4, precisely so a window
called `DEFAULTS` is not silently grounded. Net effect: the token did
nothing at all. `newshell "CCON:0/18/640/130/DEFAULTS"` produced a
window titled `CCON:` — neither grounded nor titled, the name simply
dropped. Titles of `DEFAULTS`, or anything beginning `CONFIG`
(`Configuration`), were legal before b14.

This also made a line in b15's boot checklist untrue as written; it
had been ticked with the batch without being exercised.

Fix: `cfgisdirective()`, the same question with no side effects, and
field 4 asks it before deciding. `IF cfgisdirective(tok) OR
(parseopt(tok) = FALSE) THEN` title. The f=0 shortcut is untouched.
Harness section R, 7 checks including the pure-predicate property
that it grounds and selects nothing.

**F2 — the arrow walk out-ranked a live content search.** *(defensive,
fixed)*

b12's intercept sits above both the close-on-any-key block and
`dorawkey`'s `sbsrch` arrow handling, so with both live the menu
would eat arrows the search owns — the exact hazard the C9 note
warns about.

Not reachable today: `sbenter()` needs `viewoff > 0`, and every way
of scrolling back (plain arrows now walk the menu, Ctrl/Shift arrows
and the wheel all pass through the close block first) closes the
menu before the view moves. But that is an invariant proved three
procs away and one edit from being false. `AND (curcon.sbsrch =
FALSE)` on the intercept costs one term and removes the dependency.

**F3 — `iconload` adds a blocking point at iconify time.** *(recorded
behaviour, no change)*

`iconload` does `CreateNewProc` + `Wait(fhsig)`, blocking the whole
handler process — every CCON window it serves — until the helper
signals. Same shape as `fontload`, but `fontload` blocks during
`openwin` where a window is being built anyway, while this blocks
inside the event drain on a gadget click. Bounded by the same thing
that bounds `fontload`: one filesystem round trip, and audit2 P6's
no-timeout note already covers a wedged volume. Once per console, and
only for a console that both sets `ICON=` and is iconified.

**F4 — `tcadd`'s `dev` arm re-sets bit 0.** *(cosmetic, no change)*

`IF dev THEN p[0] := p[0] OR 5` sets bits 0 and 2, while `isdir`
above has already set bit 0 for the only caller that passes `dev`.
Harmless and idempotent, and the OR-5 is what makes the flag correct
if a future caller ever passes `dev` without `isdir`. Left as is,
noted so the redundancy reads as deliberate.

## Verified clean

- **The ICON= lifetime**, the one that could have crashed.
  `killhandler` closes `iconbase` *before* anything would call
  `FreeDiskObject`, which would be a use-after-close — except
  `ACTION_DIE` refuses while `conlist <> NIL`, so every console has
  already been through `conclose` → `condispose` → `FreeDiskObject`
  by the time the library closes. Sound by construction, and the
  construction is load-bearing: if `ACTION_DIE` ever stopped refusing
  a busy device, this becomes both a leak and a bad call.
- **b11's `tcdrop` in `doresize`.** Everything between it and the
  full clear+redraw is state assignment and model-only work
  (`clearsel` state, `dropeditmirror`, `gridcalc`); nothing needs the
  menu rows painted. The pixels are owed by the redraw regardless.
- **`loadcfgfile`'s allocation.** All four exits `Dispose(fh)` or
  never allocated; `tcfreelock()` on both paths that took a lock.
  Runs per open now rather than once per handler life, so a leak
  here would have compounded per window.
- **Stack.** `parsecon` (~200) → `loadcfgfile` (buf 256 + line 260)
  → `cfgsect` → `cfgapply` (tok 84) → `parseopt` (tok2 84) peaks
  around 1 KB of the 10000-byte E stack. `tcresolve`'s ~350 is
  returned before the read loop, and `cfgpre` returns before
  `loadcfgfile` is called, so neither is additive. Well under
  `savehistfile`'s ~2.5 KB, which still owns the mountlist's
  StackSize note.
- **`tcstem` before first use.** `String(416)` from `coninit` is a
  valid empty E-string, and the Esc path is reachable only while
  `tcactive`, which is only set after the snapshot is taken.
- **`tcgridmove` arithmetic.** `tcmcols < 1` guarded before the only
  `Mod`/`Div`; `tcshown - 1 - c` cannot go negative because
  `c = Mod(n, tcmcols)` with `n < tcshown`. Both proven in harness
  section M, including the 0- and 1-entry grids.
- **`cfgapply`'s ICON copy.** Bounded at 102 into a 104 array with
  room for the terminator.

## Verdict

The config campaign held up better than the palette campaign that
preceded it, and for a structural reason: `parseopt` stayed the
single place an option is applied, so the file and the open string
could not drift, and the whole precedence rule reduced to the order
of three calls. Almost everything the audit could have found there
was found by the harness first — 153 checks over nineteen procs
extracted verbatim.

Both real findings are at the seams, again, and both in the same
place: where a NEW keyword meets the field-4 title rule (F1) or an
EXISTING key-consumption order (F2). That is the third campaign in a
row where the seams were the whole story, which is an argument for
looking there first next time rather than last.

**Audit7 closed**, F1 and F2 fixed as 1.2.7b16, cfgtest 153/153,
**boot-verified 11.8.26** ("All green") — including the field-4 title
case F1 had broken, which is the one the b15 checklist had ticked
without exercising.

---

# Audit8 — the 1.2.8 delta: the C engine and b1–b12 (6.10.26, vs 1.2.8b12 @0e45b7b)

Read-only pass over everything since tag `ccon-1.2.7`: ~3,300 lines of
E, `engine.c` (1,500), `pgroups.s` (1,800), the build and the
differential harness. Five parallel read passes (the C engine; its E
glue; b1–b6 features; b7–b12 features; whole-file sweeps + ledger +
docs/tests), then the top findings re-checked against the cited lines
before being written down. Nothing in the source was changed.

Rebuilt in /tmp as a baseline: `engine.bin`, `con.h` and the
`ccon-handler` binary are all **byte-identical** to the committed ones;
`fxdiff` (needs `vamos -C 68020 -m 8192`) gives 7200 chunks, 0
mismatches. So the committed binaries are the source, and `frun`
matches `render()` for every input fxdiff generates — the findings
below are all in places fxdiff does not reach.

**Status (6.10.26): batch 1 shipped as 1.2.8b13** - J1, J2, J4, J5,
J7, J10, J11, J12, J14, J15, J16, J18, J19 fixed; J1 and J4 proven on
FS-UAE stock with `tests/a8test` (b12 fails, b13 passes), the rest
await the boot checklist in todo.md.
**Batch 2 shipped as 1.2.8b14** - J8, J9, J23 (activation; the stale
pens half is left), J24. J9 proven on FS-UAE with marker builds that
reopen 200 px narrower: b13 comes back empty, b14 rewrapped and live.
**Batch 3 shipped as 1.2.8b15** - J3 (dgsync before every direct
paint; a marker build showed b14 painting window A with window B's
cache, b15 never), J6 + J17 (fit and position re-checked under the
layer lock, in C and E; a marker + planted-refusal control showed no
false refusals on a normal window).
**Batch 4 shipped as 1.2.8b16** - J13, J20 (trailing `*` only; the
mid-word-quote half is the deliberate, tested `dh0:"my dir"/x`
behaviour and stays), J21 (proven on the A1200: b16 completes from an
ADDed C: directory, b15 does not), J22, J25 (FAST only when every
flushed console asked for it), J26. Not done: J27 (bold smear, needs a
pixel look), J28 (harmless). L1's two stale Div comments corrected.
**Batch 5 shipped as 1.2.8b17** - J29/J30 (build.sh checks FXCONSIZE,
WOBSZ/DFROWS/INQMAX and the LINKED image's sections; each check shown
failing on a plant - the first section check itself missed `.sdata`
and was fixed), J31 (drain removed, entry 32 = moveq #0,d0 / rts),
fxdiff's split mode (a planted J1 fails at the first split chunk),
D1/D2 (re-copied; tests/syncheck.py now enforces it; cfgtest 176/176
with the 1.2.8 switches), D3/D4 (ccon.cfg, ccon.doc), D5 (tests
README), D6 (.gitignore). **Audit8 is closed** except J23's stale-pens
half and J27 (bold smear), both cosmetic and written down.
**After the close (1.3.0b18, 6.10.26):** J23's stale-pens half FIXED -
attr bit 7 marks a translated fg (E and C curattr alike, fxdiff clean),
hidewin keeps anstab in oldtab, reopenwin's retranslate() rewrites the
marked cells when the table changed; a marker build that records a
rotated table shifted every bold colour by one on restore, the real
build left them alone (FS-UAE 16 colours). J27 NOT REPRODUCED on the
A1200: bold topaz 8 and MicroKnight 8 stay inside their cells (the
glyphs leave the last column empty, the smear fills it) and a row
overwritten plain is pixel-identical to a plain one (tests/boldtest);
the ccon.doc limitation added in b17 was withdrawn.

Fresh series **J1..** for code, **L** for ledger, **D** reused for docs
drift within this section only. Confidence: **C** = confirmed by
tracing or measurement, **P** = plausible, not reproduced.

## Findings — fix before 1.2.8

**J1 — a sequence split across two flushes is painted as text, and
poisons the next E render.** *(wrong output, C)*
`cfout` (engine.c:1315-1318) has no `c->cesc` test, and engine.c never
reads `cesc`; `frun` starts the buffer fresh at byte 0 (:1344). E only
calls `frun` at `cesc = 0` (8655-8660), but `flushout` → `cfout`
(2195) and `wchar` → `cfout` (engine.c:1404) skip that guard.
Writer sends `ESC [ 3`, flush tick, writer sends `1mRED…` → `1mRED`
is drawn as text, `cesc` stays 2, and the next E render eats the
prompt's digits into `cpar` and runs `S` as a CSI final (scroll 31).
With an OSC split, everything later goes into the title. Likely with
chunked ANSI writers whenever the paced timer flushes between writes.
fxdiff cannot see it (whole items per chunk). Fix: `|| c->cesc` in
cfout's bail list. Add a split-sequence mode to `mkdiff.py`.

**J2 — TABREQ: the requester's answer is always lost, and the handler
can never unload afterwards.** *(hang/wrong behaviour, C)*
`Wait()` (1150) clears the signals it returns, `arsig` included (in
the mask, 1147). `ardone` (3440) then polls `SetSignal(0,0)`, finds
nothing, returns; `arbusy` stays TRUE for good: nothing inserted,
every later empty Tab beeps, ACTION_DIE refused (2018). Works only
if the helper signals between `Wait` returning and `ardone`. The b6
boot checklist is unticked. Fix: test `msigs AND arsig` as well.

**J3 — one glyph cache serves every console.** *(wrong output, C)*
`dgtf/dgch/dgl` are globals (551-553), rebuilt only by `dggo` via
`dpprobe`, which runs only from `gridcalc` (3090) — at open/resize of
*that* console. `dpaint`, `dprowp`, `ppsetup` and `cfout`'s key all
trust the global. Console A (screen font) then B with `FONT=xen/8`:
A paints with B's glyphs; with different heights (8 vs 11) A is
garbled (stride mismatch; stays inside the 8 KB buffer, no crash).
Fix: re-`dggo(curcon.rp.font)` when `dgtf`/`dgch` differ before every
direct paint, or key the cache per console.

**J4 — WAIT_CHAR timeouts lose their sub-second part.** *(wrong
behaviour, C — measured; since M4 @c96c863)*
`armtimer` 1721: `Mod(us, 1000000)`. E-VO's `Mod` uses the divisor's
low word only (1000000 AND $FFFF = 16960): `Mod(50000,1000000)` =
16080 under vamos. `WaitForChar(fh, 500000)` waits ~8 ms. `Div` (1720)
is a full 32-bit divide and is right. Fix: `us - Mul(secs, 1000000)`.

**J5 — after a resize the jump step can exceed the rows: negative
cursor row, heap writes.** *(corruption, C by reading)*
`gridcalc` clamps `jeff` to `rows-1` (3078-3080) *before* `doresize`
lowers `rows` to `sbmax-2` (5114); `jeff` is never re-clamped. The
next bottom newline sets `cy := rows - jeff` < 0 (E 6892/7992,
engine.c:224/259) and `lfrun` writes `sw[negative]` — before the ring
allocations when `sbtop < -cy`. Reach: `LINES=100 JUMP=98+` and a tall
RTG window, or the auto step after the b8 memory halving left the ring
near `rows+2`. Fix: re-clamp `jeff` after 5114 (or move the `sbmax`
clamp into `gridcalc`).

**J6 — the direct painters do not clip to the window; a shrink
paints outside it.** *(wrong output, C)*
`doresize` flushes (5020-5021) before `gridcalc`, with the old
`cols/rows`. `cfout`'s key has no size, the one-cliprect test still
passes, and `ppaint/prowm` paint the old grid over the new border,
the size gadget and whatever was uncovered. `dpplanar` and RTG
`dpaint` have the same hole; `Text()` always clipped. Not memory
corruption (inside the screen bitmap). Fix: under the layer lock,
require the grid to fit the layer minus borders, else fall back.

**J7 — completion menu left open across `hidewin`; a SetMode then
draws through a NIL RastPort.** *(crash, C path / rare trigger)*
`hidewin` (4095-4140) sets `rp := NIL` but never `tcdrop`s.
`ACTION_SCREEN_MODE` raw (1934-1945) → `tcclose` → `drawmodelrow` →
`drawmrow` (5592) → `SetAPen/Move/Text` on NIL. Tab menu open, the
Workbench closes (b9 screennotify) or the window iconifies, a second
client of that console sends SetMode. Without the packet: after
reopen `tcactive` is still set and a changed row count makes `tcclose`
paint below the grid. Fix: `tcdrop()` in `hidewin`, as `doresize` does.

**J8 — the painter context `pkey`/`pctx` is never invalidated.**
*(corruption, P)*
Written only in `ppsetup` (7368, 7405); no clear in `hidewin`,
`closewin`, `snmsg`, `gridcalc` or `reopenwin`. `pctx` holds absolute
plane pointers. Workbench changes mode (b9 hides and reopens the
windows at the same place, same font): if the new BitMap struct lands
at the freed old address — likely with first-fit and an equal-size
allocation — the key matches and `cfout` paints into the old screen's
freed chip planes. Fix: `pkey[0] := 0` in `hidewin`/`closewin`/
`gridcalc`, and once at startup.

**J9 — screen-mode reopen: scrollback dropped, and a shorter window
leaves the cursor below the grid.** *(wrong behaviour, C)*
`reopenwin` disposes the whole model if `cols <> sbcols` (4263) —
different border widths or Intuition shrinking the window (no
`WA_AutoAdjust`, 4166-4186) — so the changelog's "come back … with
their scrollback" fails, and with `sb = NIL` the console loses the C
engine and direct paint for life. If OpenWindow fails, `wbgone` stays
set and writers stay parked until the next Workbench reopen. With
fewer rows but the same cols, none of `doresize`'s shrink fixups
(5144-5185) run: `cy/ancy = rows`, the edit line paints over the
bottom border and the mirror overwrites the oldest history row until
the next newline. Fix: share `doresize`'s reflow and shrink code with
`reopenwin`.

**J10 — `curserase` ANDs two pointers.** *(wrong output, C — since
0.12)*
5710: `IF curcon.win AND curcon.sb` — bitwise; two valid addresses
with no common bit test FALSE, the raw block cursor is never erased
but `cursx := -1`: Ed leaves complement blocks, and masked renders
leave plane droppings (breaks the plane-mask invariant). More likely
on chip-only machines. Fix: `(win <> NIL) AND (sb <> NIL)`.

**J11 — a key drained while the window is hidden throws away the
parked writes.** *(data loss, C effect / narrow race)*
`ihkey` 10801 calls `flushwq` with no `win`/`wbgone`/`appicon` check;
`dowrite` re-parks each packet at the tail (2057-2065) until WQMAX,
whose overflow arm replies "accepted" and drops the data, then
`wqn := 0`. Trigger: typing as the Workbench closes or the window
iconifies. Fix: require `curcon.win <> NIL`, or snapshot `wqn`.

**J12 — Tab / Alt+Tab while scrolled back paint over the scrolled
view.** *(wrong output, C — root pre-1.2.8)*
The `$42` branch (10450-10458) calls `snaplive` only under `sbsrch`;
the general one (10557) comes later. `drawedit`, the menu and `tcclose`
then paint live rows into a scrolled screen. The b5 scrollbar makes
the scrolled state an everyday mouse action. Fix: `snaplive()` there
when `viewoff > 0`.

**J13 — Alt+Tab/TABREQ can follow a dead process.** *(crash, P)*
`tcclient` (11020-11032) falls back to `breaktask` when no read is
queued — the last *writer*, which may be a `run` job that has exited.
`tcscancmd` then walks `proc.cli → commanddir → pathnode` (11893-11906)
and PutMsg()s to the result; `tabreq` locks `proc.currentdir` (3402).
Plain Tab had a smaller exposure since M5b. Fix: no completion that
needs the client's CLI unless a read is queued (or validate the task
against the system task lists under Forbid).

**J14 — write-accept length overflow.** *(corruption, C — very
unlikely trigger)*
`wacc` (engine.c:1162) `k->wolen + len > WOBSZ` and `swaccept` (2281)
`(wolen + arg3) <= WOBSZ` wrap for `len` near 2^31; `abcopy` then
copies far past `wob`. `dowrite` tests `len > WOBSZ` first (the audit4
D1 shape). Fix: `len > WOBSZ - wolen` in both.

## Findings — smaller

- **J15 Ctrl+H deletes a path component.** (C) `dovanilla` 10259
  matches vanilla 8 + Control, which is Ctrl+H as much as
  Ctrl+Backspace. Test the raw code `$41`.
- **J16 Custom screens count as the Workbench.** (C) `snmsg` 3228:
  `scr.flags AND WBENCHSCREEN` — `CUSTOMSCREEN` is `$000F`. Use
  `(flags AND SCREENTYPE) = WBENCHSCREEN`.
- **J17 Painter geometry checked outside the layer lock.** (P)
  `cfout` checks `pk` (engine.c:1321), runs all of `frun` unlocked,
  then `cflush` locks (1245) and paints at the cached position. An
  opaque move landing in between paints at the old place. Re-check
  `pk[1..2]` after `LockLayerRom`.
- **J18 Scrollbar scrolls skip the flush.** (C) `vsstep`/`vsdrag`
  (4025-4038) call `scrollview` without `flushout`; the next flush
  tick's `snaplive` yanks the view back. `flushout(curcon)` first.
- **J19 `inputbase` is set only inside the input-chain setup** (1106)
  and never initialised otherwise; the b7 drop modifiers call
  `PeekQualifier` when it is non-zero (3597). Set it NIL early.
- **J20 Ctrl+P quoting.** (C) A trailing `*` inside quotes (`copy
  "a*`) makes the inserted closing quote an escaped one (9973-9978,
  10027-10030). (P) a `"` mid-word opens a quote, unlike ReadItem;
  `FROM=x` repeats with its keyword.
- **J21 Alt+Tab** reads only the first directory of a multi-directory
  `C:` assign (11094-11098), and keeps scanning after the 80-entry
  list is full (11759-11790) — on a big or network Path that freezes
  every window for the length of the scan. Break on `tcmore`. Note:
  audit2 P6 (no fscall timeout) now also covers every Path volume.
- **J22 Jump-scroll slide-back** is cancelled by harmless CSIs
  (cursor on/off, DSR, window bounds, modes: 8054, 8804); and
  `jsettle` (6727-6770) does not refuse while `tcactive` (P: menu
  debris), and undoes a Ctrl+L made during a pending jump.
- **J23 Reopen keeps old pens** in the attr plane after a depth or
  palette change (4195-4242; P, cosmetic), and `WA_ACTIVATE TRUE`
  makes the last reopened window the active one.
- **J24 `killhandler`** (1327-1345): if `RemWorkbenchClient` fails 50
  times, `snport` is deleted and the library closed while still
  registered. Keep them instead.
- **J25 PACE is per console but its effect is global** — one global
  `fdelay` (581); one `PACE=FAST` window paces the others for a burst.
- **J26 `wchar` skips the waiting-reader blip** that E's `flushout`
  draws at `wolen = 0` (engine.c:1404-1409 vs 2186-2193). (P, cosmetic)
- **J27 Bold smear** reaches 1 px into the next cell (or the border on
  the last column) and is left behind when the cell is redrawn plain.
  Also unconfirmed: whether ROM `Text()` advances by `tf_BoldSmear`
  per char on a multi-char bold run — worth a pixel A/B.
- **J28 The painter reads up to 4 bytes outside the ring** at row 0 /
  the last row (engine.c:1062-1064, pgroups.s GCHARS); read-only and
  masked, harmless without an MMU.

## Maintenance

- **J29 The E↔C contract is only partly checked.** `FXCONSIZE` (145)
  is hand-written; `fcheck` probes 8 fields but not `blipdefer`,
  `bliptick`, `jsync`, which the engine uses after `osct`; `WOBSZ`,
  `DFROWS`, `INQMAX`, the `fxtab` order and the `pctx` layout are
  agreed by hand (all agree today). Have build.sh emit FXCONSIZE and
  the constants from one source; probe the last field.
- **J30 build.sh's no-data check** greps the `.o` section names only;
  `.sdata`/`.sbss`/COMMON would pass and `objcopy -j .text` would
  silently drop them. Check the linked ELF for any allocated section
  other than `.text`. (Today's build is clean.)
- **J31 `drain` (entry 32) is dead** and tests packet type 8
  (LOCATE_OBJECT) where ACTION_WRITE is 87, and calls `sendio` without
  a NULL check. Delete it or fix it before reviving.
- **fxdiff's reach:** covers `frun` and all it calls; does not cover
  `cfout`, `cflush`, `wacc`, `wchar`, the painters, split sequences or
  `?`-private sequences — which is where J1, J6, J14 and J17 live.

## Ledger

- **L1 (from J4):** audit1 "P2 Mod/Div ✓" and Audit6's "no new
  Mod/DIVS hazards" are stale — `armtimer`'s `Mod` was missed by every
  pass. The comments at 2350 and 7860 ("E's Div is 32/16") are wrong
  about `Div` (harmless).
- Every other row re-checked against 1.2.8b12 still holds, including
  where the C engine took the code over: Audit6 F1 (`rawscr` counted
  in C `dfscroll`/`lfrun`), A10 (`alteat` cleared on all three render
  exits), the plane-mask invariant (except J10, pre-existing),
  flush-before-observe (except J18), D1 (`wacc` `len < 0`), D3, C1
  (survives the b8 halving), A1/A2/A6/A7/A11, Audit7 F1/F2, and F3's
  stack note (C frames < 1 KB; `savehistfile` still the deepest).

## Docs and tests drift

- **D1** `tests/dplinetest.e:108` has `AND.B #3,D0`; the handler has
  `#11` (b9 bold) — no longer the verbatim copy the README claims.
- **D2** `tests/cfgtest.e`'s `parseopt` lacks every 1.2.8 option
  (NOINFO…NOTABREQ, PACE, JUMP, DIRECT/NODIRECT/DPFORCE): the byte-diff
  step has not been run since 1.2.8 (or fails).
- **D3** `ccon.cfg`: JUMP "0 (the default) is off" — the default is
  automatic since b8, `JUMP=AUTO` missing; LINES "floored at 100" no
  longer always true after the b8 halving; DIRECT/NODIRECT missing.
- **D4** `ccon.doc`: history "32 entries" (545) vs `HISTMAX` 200;
  LINES floor (264, 1107); b9 screennotify, bold and the own underline
  undocumented; requirements (76) omit 68020 for the C engine,
  asl.library for TABREQ, optional screennotify.library; header still
  1.2.7. `ccon.readme`/`README.md` 1.2.7-era (expected pre-release).
- **D5** `tests/README.md` never mentions `mkdiff.py`/`fxdiff` (the one
  test of engine.bin against E, and its `-m 8192` need), nor ccinfo0,
  edargtest, ederasetest, fpwtest, histdeduptest, hordertest,
  masktest, sbresizetest, srbench.
- **D6** `.gitignore` covers none of the build output: `engine/*.o`,
  `engine-0.*`, `conoffs.i`, `fxdiff*`, the compiled tests, and
  `cutils/{Install,vinstall,vinstall.e}`.

## Verified clean (highlights)

`frun` vs `render()` byte class by byte class (and fxdiff 0/7200);
the flush timer lifecycle (one SendIO under `flusharmed`, AbortIO +
WaitIO before teardown); the C side never reads the packet port;
`wacc` refuses exactly where `acceptreset` would act; `cfout`/
`cfresume` hand-over and `curcon` restore; b11 row lengths on both
sides (every non-zero writer `slfull`s; reflow `slall`s; `slsize`
bounds); the asm ABI (saves, library offsets, struct offsets, every
entry gated on 68020 by `fastok`); PIC/no-data today; the resident
walk under Forbid; Ctrl+P bounds; word jumps; JUMP parse and the
1-row case; scrollbar gadget lifecycle and divide-by-zero guards; the
ASL helper's buffers and its own process; close/reopen order and
per-window IDCMP; every ACTION_* replied once; `New`/`Dispose` and
signal/library pairing. E-VO pads `CHAR` data to even, so the INCBIN
stays aligned whatever the version string's length.

## Verdict

The C engine itself is sound: it matches E wherever fxdiff can look,
and the binaries are reproducible. The trouble is again at the seams,
and specifically at the seams of *state the C side caches or skips*:
`cesc` across flushes (J1), the glyph cache and `pkey` across consoles
and screens (J3, J8), the window size and position across a resize or
move (J6, J17). The b9 Workbench closing is the other cluster (J7–J9,
J11, J16): `hidewin`/`reopenwin` were written as a lighter cousin of
`closewin`/`doresize` and miss what those do. Suggested order: J1, J2,
J4 (one-liners, high reach); J3, J5, J10, J14 (small); then the
`hidewin`/`reopenwin` batch (J7, J8, J9, J11, J16) as one piece;
then J6/J17 (clip and re-check under the lock); then the rest.
Extend fxdiff with split sequences and a `cfout` driver so J1's class
is caught by the harness next time.

---

# Audit9 — the 1.3.x delta and whole-file sweeps (24.10.26, vs 1.3.1b1 @2afa279)

Read-only pass over `$VER: ccon-handler 1.3.1b1 (14.10.26)`: the delta
since Audit8's baseline 0e45b7b (the Audit8 fix batches b13–b17,
1.3.0b18's hidden-entry pen and J23 retranslate, 1.3.0, 1.3.1b1's
CHANGE_SIGNAL fix), then three parallel whole-file sweeps (packet
protocol and lifecycle; bounds, parsing and UI state; the C engine,
asm and the E↔C contract), then the ledger and the docs. Every
finding below was re-checked against the cited lines before it was
written down. Nothing in the source was changed. Clean-room: nothing
under `~/Projects/research/` was read.

Rebuilt in /tmp as a baseline: `engine.bin` (19752), `con.h`,
`conoffs.i` and `ccon-handler` (163564, `ecompile … LARGE ADDBUF=1`)
are **byte-identical** to the committed ones; fxdiff (`vamos -C 68020
-m 8192`) gives 7200 chunks, **0 mismatches**, on four seeds (default,
7, 12345, 999), split-sequence mode included; `tests/syncheck.py`: 0
drifted copies. The engine itself came out clean again — the findings
are in the E handler's packet and window lifecycle, the line editor
and the parser.

**Status (25.10.26): fix batch in 1.3.1b2** - see todo.md "1.3.1b2" for what
is fixed, what was verified in FS-UAE and what is still open.

Fresh series **K1..** for code and maintenance, **T1..** for docs and
tests drift (the letters I, K, N, Q, R, T, U, Y, Z were unused).
Confidence: **C** = confirmed by tracing, **P** = plausible, not
reproduced.

## Findings — fix before the next release

**K1 — Ctrl+C can Signal() a task that has exited.** *(crash /
corruption, C — pre-existing)*
`dovanilla` 10436-10439: `Signal(curcon.breaktask, …)` with no liveness
test. `breaktask` is overwritten by every READ (1905), WRITE (2115,
`swaccept` 2328, engine.c `wacc`) and open (3101), and cleared only
when the last handle closes (1866). Everyday trigger: `run list` in a
shell. The shell writes its prompt and queues its READ (breaktask =
shell); `list` writes (breaktask = list); `list` exits — its END does
not touch breaktask because `opens` is still > 0; the user presses
Ctrl+C at the prompt and `Signal()` writes `tc_SigRecvd` of a freed
Task, and if the freed `tc_SigWait`/`tc_State` happen to match, Exec
re-links "it" into TaskReady. J13 added `taskalive()` (11260) for
Alt+Tab only; the Ctrl+C path, the older and commoner one, never got
it. A reply port in PA_SOFTINT mode has an Interrupt, not a Task, in
`mp_SigTask` — the same hole. Fix shape: `taskalive(breaktask)`
before the Signal, falling back to the head reader's task; at
ACTION_END, revert `breaktask` when it is the closing sender's task;
only take `mp_SigTask` from PA_SIGNAL ports.

**K2 — the 1.3.1b1 CHANGE_SIGNAL target is undone by the next write.**
*(wrong behaviour, C)*
1990-2010 sets `breaktask` from the port, but the next WRITE from any
task (2115, 2328, engine.c:1166), READ (1905) or open (3101) replaces
it. The 1.3.1b1 proof was `Wait 30 | cat`, whose last stage writes
nothing. With `list sys: all | cat`, cat's writes move the break to
cat and csh's relay task never sees Ctrl+C — the pre-1.3.1b1 symptom
back for every pipe that prints. The Guru Book (21.2.4.3, via
amigados-handlers.md) and CTerm's policy: the CHANGE_SIGNAL target
stays; a READ may replace it; a writer takes the break only while
nobody is set. Fix shape: a `breakset` flag set by CHANGE_SIGNAL with a
non-zero arg2, cleared by READ (and by a CHANGE_SIGNAL back to the
shell); WRITE/`wacc`/`swaccept` set `breaktask` only when it is clear.
(Couple with K1: the stored target must still be checked alive.)

**K3 — input events still in the ring run against a console that
hidewin has just closed, and paint through `rp = NIL`.** *(crash, C
path / narrow trigger)*
`hidewin` (4157-4222) sets `armed`, `win`, `rp` to NIL but does not
scrub the ring's `e.con` tags, as `conclose` does (1722-1727);
`ihdrain` (10978-10997) checks only `conok(c)`. RA+I is handled inside
the drain (`ihkey` → `doiconify`), so any key or wheel tick captured
behind it in the same drain reaches the hidden console: wheel or
Shift+Up → `scrollview` (6675) → `redraw` → `drawmrow` on rp NIL;
Tab → `tcmenudraw` → `SetAPen/Text` on NIL (rp->FgPen lands at address
25, in the exception vectors). `redraw`/`scrollview` guard only `sb`,
which hidewin keeps. The handler is likeliest to lag behind the ring
while output streams. The Workbench-close hide (snmsg) has the same
shape with a smaller window. Fix shape: scrub `e.con = c` in hidewin,
or skip slots whose console has `win = NIL` in ihdrain (nested IFs —
E's AND does not short-circuit).

**K4 — the window pointer DISK_INFO hands out outlives hidewin.**
*(corruption / crash, P — since 1.2.6's iconify, widened by b9)*
DISK_INFO puts `curcon.win` in `id_VolumeNode` (2042); the comment at
2014 says Ed's menu strip and More's retitle "both hang off this
pointer", and processes that take `pr_WindowPtr` from it keep it for
DOS requesters. `doiconify` (RA+I, the iconify gadget) and `snmsg`'s
Workbench close call `hidewin`, which CloseWindow()s it; `reopenwin`
opens a new window, possibly at another address, and nothing fixes
those pointers. Ed's ClearMenuStrip at exit, More's SetWindowTitles,
or a "please insert volume" requester then use freed memory. The 1.2.6b4
boot run "gadget over Ed parks and restores … no guru" (todo.md 4314)
is consistent with the new window landing at the old address
(first-fit, same size) and proves nothing on an MMU-less machine; Ed's
menus are also simply gone on the new window. Test: Ed, iconify,
restore, try Ed's menus; then quit Ed under MuForce/Mungwall in
FS-UAE. Fix shape: refuse iconify while `rawmode` (as CTerm refuses a
screen switch while a console is raw, amigados-handlers.md); for the
Workbench close, which cannot be refused, walk TaskReady/TaskWait under
Forbid and set `pr_WindowPtr = oldwin` to NIL, back to the new window
on reopen; write the Ed/More limit into ccon.doc.

**K5 — Return commits a line into the input queue with no room check;
a full queue keeps half a line and glues the next command onto it.**
*(wrong behaviour / data integrity, C)*
`dovanilla` 10404-10407: `FOR j … enqueue(s[j])` then `enqueue(10)`;
`enqueue` (12780) silently drops on full (`INQMAX` 2048). Trigger:
Shift+RA+V (or PASTEEXEC) with a 6 KB script — `dopaste` feeds every
byte through `dovanilla` with no packets served in between; the queue
fills inside line k, the rest of k and its LF are dropped, every later
line is echoed but lost, and the queue ends in an unterminated piece of
k. The user's next command is appended to it (`delete ram:` + whatever
comes next). Type-ahead of long lines while a command runs hits the
same path more rarely. The raw paste path already detects this
(`trunc`). Fix shape: `IF inqroom(l + 1) = FALSE` → beep and keep the
line in `ebuf` uncommitted; stop `dopaste`'s exec loop at the first
refused commit.

**K6 — the 8-bit OSC introducer $9D swallows UTF-8 text.** *(wrong
output, C — E and C alike)*
`renderx` 9091-9093 (`c = $9D` → `oscstart`) and engine.c:746; the OSC
body (9045-9063) eats every byte, LF included, until BEL, $9C or ESC \.
UTF-8 ” is E2 80 9D and “ is E2 80 9C: `type README` with curly quotes
goes blank at the first ”, and the next “ ends the "OSC" and retitles
the window with the swallowed text. Stock console.device has no $9D
OSC. (The $9B CSI introducer has the same UTF-8 clash — `ś` is C5 9B —
but matches stock behaviour; note only.) Fix shape: drop the $9D
introducer (keep `ESC ]`) in both E and C, or at least end the OSC
body on any C0 control; regenerate fxdiff.

**K7 — after a shrink the edit line can be taller than the grid;
drawedit mirrors it into ring rows below the screen and paints it
over the border.** *(scrollback corruption / wrong output, C by
reading)*
`drawedit` 9512-9530: the mirror loop runs `r := ancy …` with no
`r <= rows-1` guard (CopyMem to `visrow(r)`, `slfull(r)`, `Text` at
row r; the blip read at 9587 likewise). `edroom` (9206) gives up at
`ancy = 0`; `edcap()` is only applied on typing/recall/completion;
`doresize`/`regrid`/`reopenwin` never trim `ebuf`. Scenario: a
300-character command in 80x23, then drag to the 160x60 minimum
(~18x5): ~11 extra rows land in ring slots `sbtop+5…` — on a full ring
the oldest history — and the guarded erase loops never clear them:
phantom editor text in history for good. Heap writes past the ring
need `r >= sbmax` (a cols 2-4 borrowed window or a ring cut to rows+2,
P). Fix shape: after `edroom`, if `edlastrow(l) > rows-1` trim `ebuf`
to `edcap()` and clamp `cpos` (once in `regrid` and after `reanchor`);
guard the mirror loop with `r <= rows-1`.

**K8 — the Tab menu can be placed below the grid, and long names paint
past the right edge.** *(wrong output, C)*
`dotab` 12755-12760: the make-room loop stops at `ancy = 0`, but
`tcmrow0 := edlastrow + 1` and `tcmrows` (clamped only to `rows-1` in
`tcmenucalc` 12466) are kept. A fresh NewShell in a 10-row window, an
85-character line (2 rows), `c:<Tab>` with 80 candidates: tcmrows 9,
menu rows 2..10 — row 10 is the bottom border, and `tcclose` →
`drawmodelrow(10)` paints an off-grid ring row there. And `tcmcolw` is
capped to `cols` (12465) but `tcmenudraw` still draws `l` characters
(12500): a 40-character name in an 18-column window crosses the right
border, which `tcclose` never restores. Fix shape: `tcmrows :=
Min(tcmrows, rows-1-edlastrow)` after the loop (0 rows → NOTABMENU's
cycle); clip `l` to the column width.

**K9 — an AUTO console whose window fails to open hangs its readers.**
*(hang, C path / rare trigger)*
openwin's failure arm (4489-4492) leaves `autopend := FALSE` with
`win = NIL`; ACTION_READ (1882-1898) then queues reads that no input
or EOF can ever satisfy (writes already fail -1). Fix shape: in READ,
`win = NIL` and not `autopend`/`appicon`/`wbgone` → reply -1 /
ERROR_NO_FREE_STORE.

**K10 — J9's reopen-failure half is still open.** *(hang, C)*
`snmsg` 3290-3297: a failed `reopenwin` leaves `wbgone` set until the
*next* Workbench reopen — parked writers and readers wait with nothing
retrying. `doappmsg` 3590-3598: the failed restore re-adds the AppIcon
with `iconobj`, not `c.myicon` (ICON= lost, cosmetic); if
`AddAppIconA` also fails the console is orphaned — no window, no icon,
`wbgone` FALSE — and its `wq` writers are never replied (`flushwq` not
called). Fix shape: retry on the flush timer, or fall back to
closewin's replies (reads EOF, writes accept-and-discard); flushwq on
the orphan arm; `myicon`.

## Findings — smaller

- **K11 CHANGE_SIGNAL ignores arg1.** (C, impact P) The Guru Book's
  dp_Arg1 is the handle's `fh_Arg1`; CCON routes by sender
  (`conbysender(pkt, TRUE)`, list-head guess included). A parent
  sending it for a child's handle (CreateNewProc/SystemTags with
  SYS_Input = another CCON window) retargets the parent's console, and
  the guess can redirect a stranger's. Use `conok(pkt.arg1)` first.
- **K12 CHANGE_SIGNAL's res2 can be a Task, and `breakarg` goes stale.**
  (C, hygiene) Before any CHANGE_SIGNAL, `old` (2000) is `breaktask`, a
  Task where callers expect a port (csh reads res2 as one); `breakarg`
  is never cleared when READ/WRITE move the break or at the last END,
  so a later query returns a port that no longer is the target. Return
  `pr_MsgPort` for a process; clear `breakarg` where `breaktask` moves.
- **K13 A second `?47h` while the alternate screen is up throws the
  transcript away.** (C by reading, trigger P) 8296-8301 → `altsave`
  begins with `altdrop()`: the client's own page becomes "the
  transcript" restored at `?47l`. xterm treats it as a no-op: `IF
  altvalid = FALSE THEN altsave()`.
- **K14 J23's retranslate skips the alt snapshot.** (cosmetic, C)
  `retranslate` (4224-4249) walks only `sa`; with More/Ed up during a
  Workbench mode change, `alta` keeps the old pens with bit 7, and
  `altpop` copies them back on `?47l` — or, on a changed grid, right
  after retranslate in `reopenwin` (4369-4377). Run the same map over
  `alta` when `altvalid`. Also (P): a cell that fell back to a raw pen
  loses bit 7 and is never translated again on a later palette.
- **K15 Every OSC number retitles, not just 0/1/2.** (C) 9053-9056 skip
  any digits and the first `;`: OSC 8 hyperlinks set the title to
  `;url` then `;`; OSC 7/4/52 (common over ssh) retitle too. The
  comment says only 0-2. Collect the number; title only for 0-2.
- **K16 A field-4 title beginning "Screen" or "Font" is taken as an
  option.** (C) `parseopt`'s SCREEN (2568-2582) and FONT (2795-2808)
  prefixes match with one following character; the comment's own
  example (2980-2983, "Screensaver-log" becomes the title) is false —
  it sets `pscrname = "saver-log"`, no title, silent fallback screen;
  "Fonts"/"FontEdit" override a ccon.cfg FONT=. At field 4, accept
  only the `=` forms.
- **K17 ACTION_END restores the alternate screen on any handle's
  close.** (P) 1856-1863 has no owner test: a `run` job's handle
  closing while More/Ed is up snaps their page back to the transcript
  under them. Restore only on the END of the task that entered alt.
- **K18 A hidden WAIT window dies at its last close.** (C, low)
  1864-1873 tests `c.win` only: an iconified or Workbench-hidden WAIT
  console is conclosed (icon removed, contents lost). Linger when
  `win OR appicon OR wbgone`.
- **K19 Content search can scroll past the history.** (cosmetic, C)
  `sbfind` searches to `sbcnt + rows - 1` (9865) and sets `viewoff :=
  v` (9877) uncapped: blank or wrapped live rows on top, a title of
  "[scrollback -v]" beyond the real history. `Min(v, sbcnt)` with the
  highlight row offset.
- **K20 J13's check has a time-of-check gap; the C: locks are borrowed.**
  (P) `tcclient` tests `taskalive` once; `tcscancmd` then walks
  `cli → commanddir → pathnode` (12150-12164) across `fscall`s that
  Wait — a running (not reading) breaktask client can exit meanwhile;
  `tabreq`'s `lockpath(proc.currentdir)` likewise. The J21 extra C:
  locks (12136-12159) and `tcresolve`'s first one are used after
  `UnLockDosList` without DupLock (an `Assign C: x REMOVE` race). And
  `taskalive` walks under Forbid only: an interrupt's Signal() can move
  the node it stands on to TaskReady — the walk still terminates, but
  can miss (false negative, harmless). Audit8's first option stands:
  CLI-dependent completion only while a read is queued.
- **K21 Packets after ACTION_DIE.** (P, very rare) The drain (1172-1175)
  keeps dispatching after DIE sets `dieing`: an open queued behind DIE
  builds a console killhandler never tears down; packets arriving after
  the last GetMsg are never replied. Refuse them once `dieing`; drain
  `port` last in killhandler.
- **K22 diskhelper signals without Forbid.** (P, very rare) 3184:
  unlike `aslhelper` (3437), it Signals and still runs its epilogue
  and the poked stub from the handler's memory; a DIE reaching
  killhandler and exit before the helper runs again leaves it
  executing freed code. `Forbid()` before the Signal, as aslhelper.
- **K23 J24's fallback trades a stray write for a hang.** (P) A
  PA_IGNORE `snport` never replies a later notice; screennotify waits
  for replies before letting the Workbench close, so the next
  CloseWorkBench caller would block. Better: refuse ACTION_DIE while
  `snrem()` fails, so killhandler never runs registered.
- **K24 `reopenwin`'s `changed` is computed before the ring clamp.**
  (cosmetic, C) `gridcalc` (4368) does not apply `rows <= sbmax-2`;
  `regrid` does. A window taller than its ring (small LINES, tall
  window) therefore reads "changed" on every restore: alt snapshot
  popped and re-saved, SIZEWINDOW reported, Ed's page replaced by the
  transcript until the client repaints — the "unchanged grid = nothing
  to do" promise of the J9 comment broken. Compare after the clamp.
- **K25 `ppsetup` accepts a NULL plane.** (P) 7553-7555 reject `planes[p]
  AND 3` (catches the all-ones -1 plane) but not NIL, the all-zeros
  trick: on such a custom screen pm/pm1 and `dprowp` write at
  `ay*bpr` in low memory. Reject NIL too.
- **K26 The obscured test relies on `ClipRect.lobs` alone.** (P)
  engine.c:1250 and E 7505-7508 do not test the ClipRect's own BitMap
  (`cr+12`); lobs is layers' business on 3.1, unconfirmed for 3.2's
  rewritten layers. Adding `*(LONG*)(cr+12) == 0` costs nothing.
- **K27 Hygiene bundle** (all C by reading, low):
  `loadhistfile` (11490-11500) keeps CR and control bytes (a PC-edited
  history recalls `dir\r`); ESC/$9B in a recalled line or a completed
  filename are interpreted by `render(ebuf)` at commit (10403) — filter
  <32 and $80-$9F on load and insert. CSI parameters past four
  overwrite `cpar[3]` (9073-9075, C the same): `38;2;255;128;0m` ends
  in 0 and resets SGR, `38;5;31m` sets red — skip 38/48
  sub-parameters. ESC/CAN/SUB do not abort a CSI (`ESC[31` +
  `ESC[0m` prints `0m`); ESC + anything but `\` in an OSC eats that
  byte. `shineok` 12380 / `hidpen` 12415 `Shl(1, depth)` is 0 at depth
  32 (P: GetBitMapAttr reads 8 on the user's P96 screen) — cap at 8.
  PASTEEXEC routes every byte through `dovanilla`: a pasted Tab
  completes, a pasted ESC wipes the line. `sendcpr` (8641) reports
  cols+1 at the pending wrap; a TAB at `cx = cols` wraps and then
  spaces (9105, engine.c 731). WAIT_CHAR res2 is 0 where the Guru Book
  gives the queued line count. Stale AppMessages pass `conok()` when a
  new console lands at the old address. `jsettle` on a hidden console
  clears `jslk` then returns at `win = NIL` (6891-6897), and a pending
  slide-back is likewise dropped when `?47h` arrives (J22 did not
  reach that case; same end result as before, no regression).
  ACTION_FORCE/QUEUE (ARexx) fall to DEFAULT.

## Maintenance

- **K28 genstruct.py lays out CHAR fields differently from E-VO.**
  (latent, C — measured with a probe under vamos) genstruct.py:28/:35
  round every field, CHAR and ARRAY OF CHAR included, to even and never
  round the total. E-VO packs bytes, aligns only INT/LONG/PTR and
  rounds the size to even (`a:CHAR,b:CHAR,c:LONG,…` = 0,1,2,…; a
  planted `xa:CHAR, xb:CHAR` before `breakarg`: genstruct 4228, E
  4226). build.sh would then demand the wrong FXCONSIZE, the run-time
  `SIZEOF console <> FXCONSIZE` test (8743) would switch the engine off
  silently, and a mid-object CHAR pair shifts every CON_* after it. An
  embedded OBJECT member is counted as a LONG. Today's OBJECT has only
  byte arrays that are multiples of 4, so it is right. Fix: E's rules,
  and assert on unknown types. (Worth a line in
  Knowledge/amiga/amiga-e-language.md's OBJECT rules.)
- **K29 Hand-agreed offsets build.sh does not check** (all agree today,
  by reading): pgroups.s FX_DFFULL..FX_DFX1 (1555-1561), PM_*
  (806-824), PF_* (169-185), SOFF=272, the TMP_* layout against the
  16384-byte `ptmp` (E 7558), the `pctx[0..16]` (E 7578-7594) and
  `fxtab[0..31]` (E 8711-8742) orders, `dfdb` 512 = 2×DFROWS, `dgl`
  8192. `_Static_assert(offsetof…)` in engine.c and greps in build.sh.
  J29's "probe the last field" is still open: `fcheck` stops at
  `osct[83]`.
- **K30 Local litter:** the untracked `engine/fxdiff.e`/`fxdiff` were
  built from the pre-1.3.1b1 handler (FXCONSIZE 4220); `mkdiff.py`'s
  docstring (line 10) omits `-m 8192`. `abfill/abcopy/PFILL` use `dbra`
  on n/4-1, so n < 262148 — fine for wacc's 16384, worth a comment.

## Ledger

- **Audit8 J1–J31, against 1.3.1b1:** present as described — J1 (cfout
  `cesc` bail), J2 (`ardone(msigs)`), J3 (`dgsync` in dpaint and
  ppsetup), J4 (`us - Mul(secs, 1000000)`), J5 (re-clamp in `regrid`),
  J6/J17 (fit + position under the lock, E `dpfits` and C cflush
  1256-1269, offsets checked), J7 (`tcdrop` in hidewin), J8 (`pkey[0]`
  cleared in main, gridcalc, hidewin, closewin), J10, J11, J12, J14 (E
  and C), J15, J16, J18, J19, J20 (parity traced on `"a*`, `"a**`,
  `"a*"*`), J21, J23 (both halves), J25, J26, J27 (not reproduced,
  withdrawn), J29/J30 (build.sh checks each shown failing on a plant:
  .data, .rodata, string literal, COMMON, .bss, FXCONSIZE, WOBSZ, an
  OBJECT change), J31 (entry 32 = moveq/rts, table offsets match every
  fcall). **Partial:** J9 — the reopen-failure half (K10); J13 — the
  time-of-check gap (K20); J22 — alt-screen entry (K27); J24 — the
  replacement hazard (K23); J29 — the last-field probe (K29). J28
  unchanged (harmless, as written).
- **audit3 C2 (the sbcols belt):** removed by J9 in favour of `regrid`.
  The stride invariant it guarded now holds by construction: `sbcols`
  is written at both allocation sites (4683, 5089), `cols` changes only
  in gridcalc/regrid, and every column change goes through
  `reflowring` or disposes all four planes. `retranslate` uses
  `sbmax*sbcols`. Holds.
- **audit5 A2 (DISK_INFO NIL guard), A1 (no close inside the UserPort
  drain), C3 (`conok` on AppMessages), B5 (DIE refusal), D1 (negative
  length) and Audit6 F1:** still present. Note for A1: RA+I is handled
  inside the *input-ring* drain, which is K3's opening, not A1's.
- **Still open from earlier audits, unchanged:** audit2 P6 (fscall
  timeout, parked — J21's early stop reduces its exposure on Path
  scans), audit3 P3/P4 (parked), C5 tail-pump (documented), C6
  (deliberate). The audit3 P1 wheel-redraw row was not re-measured.

## Docs and tests drift

- **T1** `changelog.md` header: "1.3.0 is built" — it is released,
  tagged `ccon-1.3.0` and on Aminet.
- **T2** `README.md` 260: release archive `ltx-cc130.lha` "on Aminet"
  — the Aminet pair is `ltx-ccon.lha`/`.readme` (todo.md 7012-7016);
  ltx-cc130 is the GitHub name.
- **T3** `tests/README.md` does not mention `boldtest` (the J27 pixel
  check).
- **T4** No harness covers CHANGE_SIGNAL, `retranslate` or `shineok`
  (hidpentest copies `hidpen` only). The 1.3.1b1 proof (`Wait 30 |
  cat`) cannot see K2; add a pipe whose last stage writes.
- **T5** `ccon.doc` (~978-1000) promises iconify "from a shell prompt
  and from a fullscreen program like Ed alike" — K4's caveat until it
  is fixed or refused.
- **T6** `ccon.doc`, `ccon.readme`, `README.md` say 1.3.0 while the
  source is 1.3.1b1 — expected for a beta; the CHANGE_SIGNAL fix is in
  changelog.md only.

## Verified clean (highlights)

Reproducible binaries (above) and fxdiff 4×7200/0; every hard-coded
system offset in engine.c (RastPort, Layer, ClipRect, Window borders,
mp_SigTask, pr_CLI/cli_StandardInput/fh_Args, AttnFlags) and the
library LVOs the asm calls; every entry into engine.bin gated by
`fastok` (020 + size + fcheck); C paints planar only, RTG goes through
E's dpaint; the cflush -1 path leaves model and marks intact and E
repaints; attr bit 7 agrees between E and C `curattr` and every
reader masks it or indexes a 256-entry table; anstab capped at 15, bg
≤ 7. `dopkt` replies exactly once on every arm, queue-full arms
included; closewin replies rdq/wcq/wq; timer pairing and the J4 split;
pen, AppWindow/AppIcon, gadget, font, lock and model lifecycles;
Forbid sections never Wait; stack (deepest ~2 KB vs E's 10000-byte
stack, no recursion). CSI parameters clamped (999, `cnp ≤ 3`), OSC
title ≤ 80, every CSI final bounded, ring index wraps, reflow, config
token caps, drag-and-drop buffers, completion list and name buffers,
`shineok`/`pendist` pen ranges, tiny-window floors.

## Verdict

The engine is done being the risk: reproducible, fxdiff-clean, and its
seams with E (Audit8's whole story) hold. The trouble has moved to two
places. First, **who owns the console's references across time** —
the break target (K1, K2, K12), the window pointer handed to clients
(K4) and the input ring's console tags (K3) all outlive the thing they
point at; hidewin is still the lighter cousin of closewin (K3, K10,
K18). Second, **the line editor and parser trusting their bounds
implicitly** — the commit into the input queue (K5), the edit line and
the Tab menu after a shrink (K7, K8), and the 8-bit OSC introducer
meeting UTF-8 (K6). Suggested order: K1 + K2 + K12 as one break-owner
rework (with a writing-pipe test, T4); K3 (a one-line scrub); K5, K6
(small, high reach); K4 (refuse raw iconify, NIL the WindowPtrs);
K7/K8 as one "fit the editor to the grid" piece; K9/K10; then the
rest. K28 before anyone adds a CHAR field to OBJECT console.
