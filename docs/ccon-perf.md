# CCON speed: conbench results analysis (23.7.26)

First conbench campaign, run by Tobias on the A1200 config (68030), one run
per console, reps 3, scale 1, sync OFF. Raw results in S: on the Amiga drive
(`conbench-{ccon,con,vinced}-results.txt`). Headline:

```
              CCON        CON:      ratio
  plain-lines  27.94s      7.00s     4.0x
  block-4k     27.34s      7.00s     3.9x
  bytewise      2.22s      0.42s?    5.3x
  scroll-nl   203.36s      0.02s?    huge
  wrap-long     8.76s      2.14s     4.1x
  sgr-colour    7.36s      4.70s     1.6x
  cursor-pos    0.92s      0.20s?    4.6x
  clear-page    9.82s      3.10s     3.2x
  erase-eol     0.96s      0.28s?    3.4x
  TOTAL       288.68s     24.86s    11.6x
```

Two caveats before the numbers get believed too hard:

- ViNCEd's 0.18s total is the deferred-reply artifact conbench's own header
  warns about (it acks writes before rendering). Meaningless without a SYNC
  run. CON:'s scroll-nl 0.02s is the same artifact - stock con-handler hands
  writes to console.device and can ack early - so CON:'s scroll and the
  '?'-flagged rows are optimistic. CCON renders before replying, so CCON's
  numbers are honest; the comparison flatters CON:. Rerun all three with
  SYNC before quoting ratios in public.
- `window: ?x?` in ALL THREE files - the CSI `0 SPACE q` probe got no answer
  even from stock CON:, so it's a conbench bug (X6 below). Geometry itself
  is NOT in doubt: Tobias resized all three windows to the same 640x246
  (borders included, tucked under the screen bar) before running, so the
  cross-console ratios stand.

## Where the time actually goes (derived per-op costs, CCON)

- **Scroll: ~34 ms per line.** scroll-nl is 6000 bare newlines: 203.36s/6000
  = 33.9ms each, and each one is a full-window ScrollRaster + ring advance
  (clearrow is model-only memory writes, negligible). This is the monster.
- **Text: ~20 ms per full 79-char line.** [WRONG - see S4 results below.
  Text measures at 1.3ms; clear-page's cost was hidden wrap-scrolls, not
  glyphs. Kept for the record of what the first-pass derivation claimed.]
- **Per-write fixed cost (cooked): ~1.9 ms.** bytewise = 1200 one-byte
  writes, 2.22s = 1.85ms each vs CON:'s ~0.35ms. Every cooked-mode write
  pays eraseedit() + drawedit(), and eraseedit's B1-era repaint loop calls
  drawmodelrow() on the whole anchor row (a full-row Text from the model)
  even when the editor has painted nothing but the 1-cell blip. Every line
  of client output is effectively drawn twice.
- **Cross-check:** plain-lines (1 line/write) and block-4k (51 lines/write)
  land at the SAME ~67ms/line, so per-packet overhead is NOT what hurts the
  line tests. [The ~67ms decomposes as TWO scrolls plus change - the wrap
  discovery in the S4 section below - not as scroll+text+double-paint as
  first guessed.] The 4K packets buy nothing today because every line
  inside the block still pays its own ScrollRaster.
- sgr-colour at only 1.6x is the tell that glyph/attr-run drawing is not the
  main gap - the scroll path and the per-write tax are.

Hardware note: on this config the CPU (JIT-ish 030) is far faster relative
to the chipset than on real iron, while the blitter runs at authentic AGA
speed - so anything blitter-bound (ScrollRaster) is capped at hardware speed
and anything CPU-bound flies. 3.2's console.device was rewritten to be fast
precisely around scrolling; CCON's one-ScrollRaster-per-line is the 1.3-era
shape. A micro-test (S4) should confirm the 34ms before major surgery.

## S4 results (srbench, run by Tobias 23.7.26 - launched from the
## Execute Command menu, which is fine: output prints after all timing)

```
window 640x245, inner 632x232, 79x29 cells of 8x8, depth 4, 200 reps
  scroll-1      34.7 ms/op
  scroll-10     31.2
  scroll-page   23.5
  text-78        1.3
  rectfill      23.4
```

What the numbers settle:

- **The scroll path is pure ScrollRaster.** 34.7ms standalone vs 33.9ms/LF
  in conbench's scroll-nl: the handler adds under 1ms per newline. Blitter-
  bound, confirmed. Nothing in screenscroll() worth touching except HOW
  OFTEN it blits.
- **S2's arithmetic is now measured fact:** ten lines in one blit cost
  31.2ms - the same as one line. Coalescing k newlines is a genuine k-for-
  one win. And k >= rows degenerates to clear cost (23.5).
- **Text is nearly free: 1.3ms per 78-char line.** The "~20ms text floor"
  from the first-pass derivation was wrong. After the scroll fixes, glyph
  drawing will NOT be the next wall - no custom rendering needed, ever.
- **The corrected attribution - the conbench windows WRAPPED.** gridcalc:
  cols = (width - borders) / 8, MARGIN = 0. The 640x246 shell windows carry
  a sizing gadget, so the right border is ~18px: cols = (640-4-18)/8 = 77.
  srbench's window has no size gadget: (640-4-4)/8 = 79, exactly what it
  reported. So conbench's 78-char lines wrap at 77 cols - every "line" in
  plain-lines/block-4k is TWO rows and, once the screen fills, TWO
  ScrollRasters. 2 x 34.7 + 1.3 text + ~1.6 tax = ~72ms vs 68.5 measured
  (first screenful scrolls less): plain-lines fully explained. clear-page:
  20 wrapped lines = 40 rows on a 29-row screen = ~11 scrolls + one 23.4ms
  FF clear per page = ~465ms vs 491 measured. sgr-colour lines are 64
  printable chars - NO wrap, one scroll - and re-derives to 7.4s vs 7.36
  measured. Every conbench row is now scrollcount x 34.7 + ~1.6ms/write,
  within noise. The handler's render code is EXONERATED; the design (one
  synchronous blit per row-advance) is the entire story.
- **Stock CON: wraps too (same 77 cols, same size gadget) yet posts
  17ms/line** - it cannot be paying 2 x 34.7ms synchronously. Stock defers/
  coalesces at the console.device layer. S5 (accept-then-render) is
  CONFIRMED as the only route to parity for line-per-packet output; S2/S3
  stand on their own for their shapes.
- Fairness note for the next conbench campaign: 78-char test lines in a
  77-col window measure wrap+double-scroll, not plain output. Either run
  wider windows or note it; X6's fixed probe would have shown 77 in the
  results file and saved a day of wrong arithmetic.

Revised expected wins: S3 turns block-4k into clear + 29-row repaint per
packet (~23.5 + 29x1.3 + model ops = well under 100ms per 4K write - from
27.3s toward under a second, FASTER than stock CON:'s 7s); S3 also merges
plain-lines' two scrolls into one blit (~68 -> ~37ms/line, 2x); S2 takes
scroll-nl from 203s to ~19s (one 31ms blit per 10-LF packet); S1 shrinks
to a ~1ms/write garnish (still worth it: bytewise 1.85 -> ~0.5ms, More's
echo path feel).

## Fix candidates, in proposed order

**S1: BUILT 23.7.26 as $VER 1.2.2b2, deployed live + staged, awaiting
boot test (checklist in todo.md "1.2.2b2").** The blip-only fast path
in eraseedit(): edlast=0 + edext<=1 + srch off + model present =>
repaint ONE normalized anchor cell (drawmodelcells) instead of full-row
drawmodelrow(s). Guards verified against source (srexit/srcancel heal
the banner themselves before any eraseedit can see srch=FALSE with a
banner up). Pixel-equivalence harnessed in tests/ederasetest.e: OLD vs
NEW lockstep over screen+model grids, 9 directed + 3000 random cycles
identical. Expected: bytewise 2.22 -> ~0.6s, cursor-pos/erase-eol ~2.5x,
sgr -1.8s. Original proposal below.
**CONFIRMED ON HARDWARE (his rerun 12:52, S:conbench-ccon-results3.txt):
bytewise 0.66 (tax 0.55ms/write), cursor-pos 0.22? = stock parity,
erase-eol 0.52, sgr 4.96 (6% off stock), clear-page 5.56. TOTAL 47.16s:
the campaign stands at 288.68 -> 47.16, 11.6x -> 1.9x of stock CON:,
with the residue almost entirely the S5 blit floor.**

**S1. Kill the per-write editor tax when the editor is empty.**
eraseedit() currently repaints rows ancy..edlastrow(edext) via
drawmodelrow() on every write. When `StrLen(ebuf) = 0` and no search banner
/ paste hint / ghost is up, the only editor paint on screen is the blip
cell: erase exactly that (drawmodelcells of 1-2 cells, wrap included)
instead of full rows. drawedit() already degenerates to blip-only at l=0.
Touches the B1/H4 minefield - edanchortest.e harness is the regression
gate. Expected: bytewise ~3x, cursor-pos/erase-eol ~2x, every cooked write
cheaper; More/raw unaffected (raw already does 1-cell curserase/cursdraw).

**S2+S3: BUILT as one engine, deployed 23.7.26 as $VER 1.2.2b1 (live in
L:, staged ccon-handler-1.2.2b1, .bak = 1.2.1), harness-passed
(tests/defertest.e: legacy vs deferred over 4010 packets, identical),
awaiting boot test - checklist in ccon/todo.md "1.2.2".** The
implementation went further than the two separate items below: ALL
sequential output within a packet is model-first (S3's shape), which
delivers S2's newline coalescing as a special case. One ScrollRaster
max per write packet; zero for screenful-plus scrolls and form feeds
(redraw-from-model instead - the FF RectFill is deleted, not deferred).
Flush-before-pixel-escapes keeps Ed/More per-op behaviour identical.
Original proposals kept below for the record.

**S2+S3 CONFIRMED ON HARDWARE (conbench rerun, Tobias, 23.7.26 12:24,
S:conbench-ccon-results2.txt, same 640x246 window):** TOTAL 288.68s ->
54.00s (5.3x; now 2.2x stock CON: overall, was 11.6x). plain-lines
27.94 -> 14.44 (predicted ~15), scroll-nl 203.36 -> 19.14 (predicted
~19), block-4k 27.34 -> 0.36? - the dffull zero-blit path, 19x FASTER
than stock CON:'s 7.00s. wrap-long 8.76 -> 2.56. clear-page 9.82 ->
6.04 vs the ~1s prediction - the prediction was wrong, not the engine:
at 77 cols a "page" is 40 rows on a 29-row screen, so the last ~6
lines of every page each carry their own 2-row scroll packet (6 x 31ms
x 20 pages = the difference; re-derived to ~5.7s vs 6.04 measured). A
>=78-col window would put it near 2s. bytewise/cursor-pos/erase-eol/
sgr-colour unchanged exactly as designed - that residue is S1's tax
(~1.6ms/write) plus S5's one-blit-per-line-packet floor.

**S2. Coalesce newline runs in render().**
A run of k LFs is one ScrollRaster of k*ch (one blit), k ring advances +
clearrows, k setwrapf(0) - and if k >= rows, skip the blit entirely and
RectFill the window once (everything scrolled off; ring still advances k).
Small, local, model math identical to k outnl() calls. Expected: scroll-nl
~10x (one blit per 10-NL packet), `type` through blank-line-heavy text
proportionally.

**S3. Write-level scroll aggregation (the block-4k fix).**
Within ONE render() call, stop blitting per wrapped/newline row: process
the packet into the model first (memory-speed), track net scroll, then do
ONE ScrollRaster (or, when net scroll >= rows, zero blits + full
redraw-from-model, which also replaces the per-line Text of scrolled-away
lines with painting only the rows that survive). This is NOT the removed
double buffer - no pixel snapshot, no screen reads; the model already
exists, rendering just becomes model-first + one paint pass per packet.
Expected: block-4k from ~27s toward ~10s; dir/list/type all write
multi-line packets. Bigger diff, needs the reflow/wrap flags kept honest -
harness + boot soak.

**S4. Measure ScrollRaster before believing anything above. [DONE 23.7.26 -
results and corrected attribution in the section above]**
`ccon/tests/srbench.e`, deployed to C:srbench. Opens its own 640x246 window
(the conbench geometry) under the screen bar and times five primitives over
REPS (default 200) iterations: scroll-1 (screenscroll()'s exact region, the
per-newline cost), scroll-10 (S2's one-blit-for-ten - this against scroll-1
is the coalescing payoff, measured), scroll-page (the k >= rows
clear-instead-of-blit case), text-78 (render()'s Move+Text shape), rectfill
(the form-feed clear). Run from any shell, window uncovered:
`srbench TO S:srbench-results.txt`. Reads on the numbers: scroll-1 ~34ms
confirms blitter-bound scrolling and the S2/S3 arithmetic; scroll-1 cheap
means the 34ms lives in the handler and the plan changes; text-78 near
20ms confirms the text floor. Also worth one diagnostic run with FS-UAE
immediate blits to prove blitter-boundness (diagnosis only, not a config
we tune for).

**S5: GREEN-LIT BY TOBIAS AND BUILT 23.7.26 - staged as 1.2.2b3 (early
reply, immediate flush - plumbing proof) LIVE in L:, and 1.2.2b4
(20ms-deferred flush, burst aggregation - the payoff) staged beside it.
Two-boot A/B plan in todo.md. Key insight that killed every half
measure: DOS Write() blocks the caller, so queue depth from one client
is always <= 1 - aggregation REQUIRES reply-before-render. Projected:
plain-lines ~2s, scroll-nl ~2s, TOTAL ~12-15s = faster than stock
overall. SYNC-mode conbench becomes the honest comparison afterward.**

**S5. (Architecture, needs a decision) Accept-then-render + burst
coalescing.** The reason stock CON: posts 17ms/line overall is almost
certainly that its handler acks the packet and lets console.device render
behind it, so bursts pipeline. CCON could copy small writes (<= 4K) into a
handler-side buffer, ReplyPkt immediately, then drain EVERY queued write
packet into one aggregated render pass (S3 then coalesces their scrolls).
Ordering stays sequential, no pixel snapshotting - but it is a semantic
shift (write returns before pixels land, exactly what conbench's header
calls out), and it deliberately reintroduces the *spirit* of deferral that
the double-buffer removal killed. Not started without Tobias's explicit
go. Without S5, single-line-per-packet clients (plain-lines shape) keep a
~50ms/line floor = the ScrollRaster + Text cost, honest but 3x CON:.

## THE SYNC-LINE HUNT (23.7.26, post-release): stock's trick FOUND

Question: stock renders a scrolled line in ~17ms where ScrollRaster
costs ~34 for the same region. Method: srbench 0.2 (candidate
primitives: ScrollRasterBF, direct BltBitMap under LockLayerRom,
CPU planar copy, and the answer below) + romtool-split of his 3.2
kickstart -> console.device 46.1 disassembled with machine68k
(lvoscan.py: JSR d16(A6) histogram; NO direct blitter access, ONE
ScrollRaster site).

**THE TRICK, decoded (site $2592, maintenance $3c00): PLANE-MASKED
SCROLLING.** console.device keeps a used-planes byte (OR of FgPen,
BgPen, cursor pen; snapped to %0001 / %0011 / $FF the moment any
pen > 3 appears; OR'd with an init floor - interleaved bitmaps
special-cased via GetBitMapAttr(BMA_FLAGS); reset to floor on
clear-screen at $08fe) and pokes it into rp_Mask - PERSISTENTLY on
its rastport ($3c4a) and again right before ScrollRaster. The
blitter then skips planes the text never touched: pens 0-3 on a
4-plane WB = 2 planes moved = HALF the blit = the whole 17-vs-34
mystery. It also passes multi-line counts to its one ScrollRaster
(muls by cell height at $2544) - their version of our S3 batching.

Persistent rp_Mask on the console rastport also PROVES Intuition
borders/title do not render through it - the approach is safe for a
handler. Plan for CCON (next b-build, needs his go): per-console
usedmask with stock's exact tier scheme (deffg starts it; grow at
the pen sources - SGR colours, ghostpen, tcmenu pens; reset to
floor on FF/dffull clear), applied to every blit+fill+text (mask
covers all pens by construction, JAM2 invariant: unmasked planes
are all-zero in the region, so skipping them is identity).
Expected: mask %0011 -> sync-line ~6.66 -> ~3.9s (stock parity);
pure pen-1 transcript -> mask %0001 -> ~2.4s, BEATING stock's 3.40
- and it stacks with S3/S5 (every dffull/flush blit halves too).
srbench 0.2 deployed (C:srbench) with mask3-scroll/mask1-scroll to
measure the factor on this machine first. cpu-1 kept as the
reference that must NOT win on real chip-bus iron.

**MEASURED (his run, srbench2-results.txt): scroll-1 34.8 /
mask3-scroll 17.4 (= stock TO THE DECIMAL) / mask1-scroll 8.8ms -
perfect per-plane linearity. Nulls: blit-1 34.8, scrollbf-1 35.2
(no layer overhead exists; the mask is the WHOLE trick), cpu-1
0.6ms = the predicted FS-UAE mirage, disqualified. Projection:
bare transcript (pens 0-1) = tier-1 mask -> sync-line ~2.1s vs
stock 3.40; tcmenu blue (pen 3) = tier 3 = stock parity; ls
colours = $FF = today. srbench 0.2 committed @cc37fc6. BUILT 23.7.26 as
1.2.3b1 (his go), deployed live + staged, .bak = 1.2.2: per-console
mpens/mmask/mfloor, growth in setpens()+curattr() only (grow-before-
draw), floor probed in gridcalc (GetBitMapAttr BMA_FLAGS, RTG-safe),
mask applied as a bracket around render() ONLY (overlay-free by
construction - ghosts/menus/banners draw AND erase at full depth,
never pollute the mask, never leave droppings). mpens never resets:
scrollback makes stock's clear-reset structurally wrong for us.
Harness tests/masktest.e: plane-level sim, 4000-op soak clean, BOTH
controls (grow-after-draw; overlay-across-masked-scroll with
position drift) corrupt as they must.**

## REAL HARDWARE (his A1200 + PiStorm32 lite / Pi CM4, 23.7.26 22:27,
## ~/Conbench.txt) - fast CPU + REAL AGA blitter, 82x53 window, SYNC ON.
## THE config that isolates true blitter cost. Ground truth, outranks
## every emulated number above.

```
              CON:      CCON            CON:      CCON
plain-lines   2.60      1.04    sgr-col 1.22      1.20
block-4k      2.54      0.64    sgr-pc  0.14?     0.08?
block-32k     2.56      0.66    cursor  0.14?     0.26?
bytewise      0.34?     0.80    vt-frm  0.32?     0.50
scroll-nl     0.18?     5.60 !! insd-l  0.00?     0.12?
wrap-long     1.52      0.48?   insd-c  0.12?     0.14?
                                clear   0.44?     0.54
                                er-eol  0.16?     0.26?
                                sync-l  0.52      1.08
TOTAL: CON 12.80  CCON 13.40  (CCON LOSES overall by 5%)
```

THE STORY IS ONE ROW: scroll-nl 5.60 vs 0.18 = 31x. That single row
is 5.4s of CCON's 13.4 total. Without it CCON 7.8 vs CON 12.6 = win
by 38%. CCON DOMINATES bulk output (plain 2.5x, block-4k/32k ~4x,
wrap 3x); everything else is parity or sub-0.5 noise.

WHY scroll-nl explodes on real iron: it scrolls a BLANK screen (each
test form-feed-clears first). We ScrollRaster empty rows - a real
blitter move on an 82x53 window (much bigger than the 77x29 emulated
runs) at authentic AGA speed, 1200 times, ~4.7ms each. CON: does NOT
blit blank scrolls (blank-skip and/or deeper queue coalescing), hence
0.18. THE EMULATOR HID THIS: FS-UAE's blitter was faster-than-real on
a big window and the window was smaller, so scroll-nl read 13-23s of
CPU-ish cost, not this pure-blitter cliff.

=> E5 (blank-scroll skip) IS NO LONGER SPECULATIVE. Real hardware
prices it at ~5.4s and it flips the OVERALL result from a 5% loss to
a 38% win. It is now the single highest-value optimization in the
whole campaign. RE-CAVEAT the 1.2.3 "fastest overall" claim: true for
bulk output, but the blank-scroll blit makes the SYNC total a slight
loss on this real accelerated config until E5 lands.

BUILT as 1.2.4b6 (23.7.26, deployed live + staged, .bak=1.2.4b5):
per-console vblank flag (TRUE=visible model provably blank -> skip
the scroll blit in screenscroll AND dfflush's catch-up; sound
because curserase/eraseedit erase the cursor BEFORE render, so
model-blank==pixel-blank at scroll time). O(1): TRUE on FF, FALSE on
any glyph, recomputed by vblankscan() at the end of redraw() (the
chokepoint every full repaint routes through). Harness: defertest
honest 4010 identical + a forced-TRUE-lie control that diverges at
the first content-then-scroll packet (proves the harness can see).
AWAITING his boot + real-HW scroll-nl (target: ~0.2 vs the 5.60 that
made CCON lose overall; would flip real-HW total to ~8s vs CON 12.8).

## *** REAL HARDWARE, b6, THE TRIUMPH (his A1200+PiStorm, 23:04,
## ~/Conbench2.txt) *** CON 12.98 vs CCON 2.54 = CCON 5.1x FASTER
## OVERALL ON REAL SILICON. E5 flipped scroll-nl 5.60 -> 0.14 (now
## beats CON's 0.18), and the full 1.2.4 stack (E1/E2/E4) collapsed
## everything else: plain 2.64->0.32, block-32k 2.58->0.02 (129x!),
## sgr-colour 1.24->0.32, bytewise 0.80->0.18, wrap 1.52->0.18.
## SCOREBOARD: CCON wins 13 rows, ties sync-line (0.54=0.54), and the
## ONLY non-win is insdel-line 0.02 vs CON's 0.00? - which is CON's
## console.device deferral piercing SYNC on a ~zero row, not a real
## loss. Essentially 15/15 on the config people ACTUALLY run
## (accelerated real HW). The 1.2.4 campaign turned the FIRST real-HW
## run's 5% LOSS (1.2.3: 13.40 vs 12.80) into a 5x WIN.
## CAVEAT: most CCON rows are now '?' (sub-0.5s) - too fast to time
## precisely at scale 1 on this machine. TOTAL (2.54 vs 12.98) and
## scroll-nl are rock-solid; for quotable PER-ROW numbers rerun at
## SCALE 4-8 so CCON clears the 0.5s trust threshold.

## THE 1.2.4 ROADMAP: 15/15 ("fastest console period", his ask 23.7.26)
## STATUS: E1 BUILT as 1.2.4b1 (23.7.26 evening, deployed live+staged,
## .bak=1.2.3): K/J/@/P/L/M/S/T model-first with dirty marks, old
## model code untouched, pixel ops skipped under dfon, all eight
## csidispatch flushes + RI's flush removed, ?47 keeps its flush.
## defertest v2 (both engines grew the ops + deterministic cursor
## jumps): PASS 4000 packets first run.
## E1 RESULTS (stock): erase-eol FLIPPED (3.64 vs ViNCEd 3.92),
## insdel-char 3.00 / insdel-line 3.38 (close), vt-frame 5.28
## (sideways - E1 traded RectFills for Text-ed blanks, E2c's bill).
## E2 BUILT as b2 (all five courses; sim mirrored gen+bounds and
## caught its own dmark/dmark2 split brain - handler never wrong).
## E2 RESULTS: stock 121.70 -> 106.76, 7/15 won (insdel-char flipped
## 2.72 vs 2.88, sync-line 5.38); dev 4.42. DIAGNOSIS of remaining 8:
## CADENCE - at 14MHz the client outruns the 20ms timer's pooling ->
## near-per-packet flushes, each paying its blit (dev pools 60/window
## and the same rows read 0.04?). Stock CON: wins these via device-
## queue backpressure. E4 BUILT as b3 (deployed, awaiting boot):
## drain-on-flush - swaccept() sweeps consecutive eligible
## ACTION_WRITEs into the batch at timer-flush time, stashes the
## first non-joiner untouched for normal dispatch after the flush;
## batch grows with load, choke paths byte-identical to b2.
## block-32k remains a per-byte CPU row (3.88 vs ViNCEd 3.04).

Row-by-row: erase-eol/insdel-char/insdel-line/vt-frame fall to E1
(K/J/@/P/L/M/S/T become model ops with dirty tracking - the S3
invariant makes the choke-flush unnecessary conservatism; L+M pairs
CANCEL in the model within a flush window = CON's own deferral
dividend). scroll-nl falls to E2c (blank-run detection in drawmrow/
redraw -> masked RectFill instead of Text-ing 29 rows of spaces per
dffull flush). cursor-pos/sgr-perchar (3-4% gaps) fall to E2a/b
(generation-counter dirty flags kill both O(rows) per-flush loops;
dirty lo/hi bounds shrink dfscroll's 3-array shifts). clear-page/
sgr-colour (tight, vs ViNCEd) need E2d/e (attr+style mirror fills
via CopyMem from a precomputed run buffer; 256-entry byte-class
table replacing the parse IF-cascade). block-32k (ViNCEd 3.04 =
46us/byte vs our 81) is the hard one: E2d/e first, E3 (asm twins
for the render byte loop + drawmrow, the ls-asm tradition) in
reserve. Victory condition = beat the PRINTED numbers (CON's
insdel-line 0.22? is SYNC-piercing deferral, matched not beaten
honestly). Sequence: E1+harness (defertest extension) -> E2a-c ->
stock remeasure -> E2d-e -> E3 only if block-32k stands. Projected
end state: 15/15 at stock timing, TOTAL ~70-80s vs stock 177.7.

## THE STOCK-TIMING CAMPAIGN (his runs, A1200-Stock config: model
## defaults, accuracy=1, 14MHz EC020, no fast RAM, Topaz 8, SYNC ON)

```
              CCON      CON:    ViNCEd          CCON      CON:    ViNCEd
plain-lines  11.50     30.26     37.14   sgr-col  20.92   24.76    16.52
block-4k      7.28     29.20     32.10   sgr-pc    8.16    7.90    14.70
block-32k     5.28     29.60      3.04   cursor    3.58    3.44     8.00
bytewise      3.12      6.26     17.58   vt-frm    5.02    3.72     3.44
scroll-nl    23.26      4.06    108.02   ins-l     4.36    0.22?    3.02
wrap-long     4.24      9.70     12.04   ins-c     4.58    2.88     4.78
                                         clear    12.40   14.42     8.54
                                         er-eol    4.78    4.06     3.92
                                         sync-l    6.00    7.22     9.68
TOTAL: CCON 124.48 / CON: 177.70 / ViNCEd 282.52
```

CCON fastest overall at authentic timing: 1.43x vs stock, 2.3x vs
ViNCEd; dominant where output flows (plain 2.6x, block-4k 4.0x,
block-32k 5.6x, bytewise 2.0x, wrap 2.3x) and sync-line still ours
(6.00 vs 7.22). THE NEW FINDING: at 14MHz the E handler's per-packet
CPU cost is a real term the fast config hid - scroll-nl is the loud
case (23.26 vs 4.06: ~19ms per 10-NL packet, only ~9 of it blit; ROM
asm does the CPU part in ~3), and it shades vt-frame/insdel-char/
erase-eol. ViNCEd: worst overall, catastrophic per-write (bytewise
17.58) but good bulk paths (block-32k 3.04, clear-page 8.54).
CON: insdel-line 0.22? = console.device deferral pierces even SYNC,
still. His epistemics caveat stands: this is FS-UAE's best A1200
approximation, NOT proven real-iron timing - release wording
"measured under FS-UAE's most accurate A1200 emulation; real-
hardware results welcome". NEXT FRONTIER (unstarted): CPU-side E
hot-path cost at real processor speeds - profile-and-tighten
campaign aimed at the per-packet path (dispatch, buffer copy, parse,
ring ops), audit-style. MK7 88x33 CCON run: 152.90 (bigger window,
consistent).

**b2 CROSS-ENVIRONMENT SOAK (his runs 16:28-16:31): CTerm borrowed
window 91x28 MK7/7 TWICE - sync-line 1.52 both, TOTALs 7.10/7.06
(repeatable to 0.6%; the fwin path + floor probe on CTerm's screen
fully validated) - and WB at MK7/7 88x33: sync-line 1.70, TOTAL
8.02. Unwrapped geometries (>=79 cols, no WARNING): the clean
single-scroll floor is ~7.6ms/line = mask-1 physics. QUOTING NOTE:
the same-geometry headline pair remains 1.78 vs stock 3.40 (both
77x29); the 1.52 has no matching stock run - an 88x33 stock SYNC
run would complete that pair if ever wanted.**

**b1 SYNC verdict (his run 16:11): the mask WORKS (plain-lines 1.22
-> 0.32? = rep-1 tier-1 blits) but sync-line unchanged 6.70 -
conbench's own sgr tests poisoned the never-reset mask for every
later test. And the analysis found a REAL b1 bug: penuse grew mmask
mid-packet but rp_Mask still held the bracket-entry value - the
first coloured packet after a plain session drew under-masked (wrong
colours once, self-healing; the sim had ONE mask variable where the
code has two). b2 (deployed): maskcalc pushes rp_Mask whenever the
bracket is open (maskon), + NARROWING under rule (c) - shrink only
right after the visible region was repainted at the OLD mask: FF
(dfnarrow after the dffull redraw / legacy after the fill), doresize
(reflow can pull coloured history INTO view - scan both ways),
altrestore (widen BEFORE repainting), reopenwin. maskscan = visible
attrs + live SGR, ~2KB. masktest extended: rule-(c) ops in the soak
+ controls C (restore, no rescan) and D (narrow before clear) - 4000
ops clean, all four controls corrupt. Conbench's per-test FFs now
re-narrow naturally: sync-line ~2.1-2.5s expected IN the standard
run. AWAITING b2 BOOT.**

## THE SYNC CAMPAIGN - the honest three-way, campaign closing table
## (his runs, 23.7.26 14:35-14:45, conbench 2.2, SYNC ON, ~77x29)

```
                CCON 1.2.2b4   stock CON:   ViNCEd
  TOTAL             18.46s       74.16s     111.68s
```

CCON: 4.0x faster than stock, 6.0x faster than ViNCEd, WITH barriers.
The reads:
- ViNCEd UNMASKED: 0.18s sync-off in the 1.0 suite -> 111.68s under
  barriers (scroll-nl 29.44 - slowest of all three - bytewise 6.20,
  cursor-pos 2.24). Its legendary snappiness is buffering all the way
  down; its rendering is the slowest on the field.
- CCON's SYNC total is within 2% of its sync-off total (18.46 vs
  18.10): the WAIT_CHAR flush is real, so CCON is the only console of
  the three whose fast numbers are also its honest numbers.
- Stock barely moved (74.16 vs 74.20), but its scroll-nl still reads
  0.02? even under SYNC - proof the SYNC probe cannot force
  console.device internals; the weak-barrier caveat stands. CCON's
  insdel-line 3.76 is real measured work where stock still hides.
- The "one test shows no output" screenshot: scroll-nl and
  insdel-line are visually BLANK by design (bare newlines / empty-row
  insert+delete on a cleared screen). conbench 2.3 (deployed,
  committed a2c84c9) prints the running test's name in the window,
  untimed, so nobody stares at a "hung" benchmark again.
- insdel variance mystery CLOSED: sub-4K workloads fit CCON's
  write-behind buffer whole, so sync-off timing swings with the 20ms
  flush phase (0.00? to 4.9s for identical work). SYNC mode is the
  honest read for those rows - as this table shows.

## conbench 2.0 campaign (his three runs, 23.7.26 ~14:00) + X6 resolved

Suite doubled + six new tests (429KB total; 2.0 TOTALs not comparable
to 1.0). CCON 1.2.2b4 vs stock CON:, both on Workbench, sync off:

```
               CCON      CON:            CCON      CON:
plain-lines    1.18     14.68   sgr-perchar  0.54    2.18
block-4k       0.68     14.68   cursor-pos   0.14?   0.40?
block-32k      0.16?    14.90   vt-frame     0.84    0.82
bytewise       0.02?     0.86   insdel-line  3.66    0.00?
scroll-nl      0.28?     0.02?  insdel-char  0.70    0.42?
wrap-long      0.80      4.68   clear-page   0.98    6.00
sgr-colour     0.66     10.56   erase-eol    0.68    0.58
                                sync-line    6.82    3.42
TOTAL: CCON 18.14 vs CON: 74.20 - 4.1x faster overall
```

The reads that matter:
- **sync-line is the honest row** (a WaitForChar barrier per line
  defeats write-behind on everyone): CCON 34ms/line = the ScrollRaster
  floor; stock 17ms/line. Stock's raw per-line render path really is
  ~2x cheaper than our full-window blit - the true remaining hardware
  gap, visible ONLY under a barrier, hidden by S5 aggregation in real
  use. Closing it would mean a cheaper scroll primitive (narrower
  region? CPU planar copy?) - a future campaign if anyone cares.
- **insdel-line inverts the optics**: CCON 3.66s is REAL work measured
  (CSI L/M are choke-flushed, ~200 half-window blits); stock's 0.00?
  is deferral - console.device blits after the clock stops. The SYNC
  campaign remains the only fair full-table comparison.
- block-32k 0.16? proves the >4K synchronous big-write path is no
  slow path (408KB/s, dffull economics). bytewise ~0 = S5 pooling.
- vt-frame parity (0.84 vs 0.82) - full-screen app repaints even.
- CTerm run (CCON borrowed window, fullscreen, no WB): same shape,
  TOTAL 16.82; insdel-char 4.00 vs 0.70 on WB = that screen's
  geometry/depth making row-tail blits pricier, not a code path.

**X6 RESOLVED (and it was two bugs):** 1.0 read the answer from
Output() - silence everywhere; 2.0 read from Input() - and the probe
ANSWERED ON ALL THREE RUNS, provable because vt-frame sized itself to
29/29/28 probed rows while the header still said "?x?": the parser
latched rows (its field ends at ';') but lost cols, because real
3.2-family replies carry pixel fields AFTER cols, so cols also ends
at ';' and 2.0 only latched it at the terminator. conbench 2.1
(deployed): every non-digit closes a field; plus the size line now
distinguishes skipped (stdin not interactive) / partial / unanswered.
One more run should print the real WxH - and, at 640 wide, the new
77-col WRAP warning.

**X6. conbench: window-size probe got no answer from any console.**
winsize() writes CSI `0 SPACE q` to Output() and reads the report back from
the same FH - stock CON: answers that request (dir uses it), so the read
side is suspect (raw SetMode on the output FH? report landing on the shell's
input FH?). Debug on the Amiga; until then the size line in every result
file is dead weight and same-geometry across runs is unverified.

## What was NOT wrong

- render()'s printable path is already run-batched (audit P1/P2 hoists are
  in and visible in the numbers - sgr-colour nearly matches CON:).
- The scrollback model is cheap: ring advance is pointer math, clearrow is
  3x cols bytes, no allocation anywhere on the hot path.
- Per-packet dispatch overhead: block-4k == plain-lines per line proves the
  packet plumbing is not the problem.

## THE J1 CAMPAIGN (14.8.26): jump scroll - the SYNC blit floor, divided

Trigger: the copper-blitter read-through (AmigaReferences/
copper-blitter-and-chip-scheduling.md). Its transferable doctrine is
the one this file already lives by - the chipset runs at chipset
speed whatever CPU drives it, blit COUNT is the budget - and under
SYNC (his chosen metric now: "SYNC is the only results I'm
interested in") the cadence is one flush per line, S5 pooling is
defeated by design, and the one ScrollRaster per line IS the
remaining bill (sync-line = 37% of the 1.2.7 SYNC total below).

J1 = JUMP=n (1.2.8b1): at the bottom margin scroll n rows in ONE
blit, land the cursor n rows up, let the next n-1 newlines print
into the vacated rows blit-free. The scroll bill divides by n.
Opt-in (default off), cooked non-alt streams only - raw/alt clients
(More, Ed) keep one-line scrolls, pixel-identical. The trade is the
classic hardware-terminal/xterm jumpScroll look: the cursor rides
the lower window instead of pinning to the last row. Semantic edge
(documented): rows enter scrollback n-at-a-time, so a clear right
after a jump leaves rows in history that scroll-by-one would have
wiped; absolute positioning mixed with bottom-margin LFs lands n-1
rows higher.

Harness: defertest v3 - lockstep at jmp 1/3/5 (full v2 alphabet,
4010 packets each, PASS), claim B (transcript invariance: history ++
visible identical between jmp=3 and jmp=1 for pure streams, wrap
flags included, blank-below-cursor proven in screen AND model), two
new seeing-controls (unclean vacated rows / cursor lands low) both
diverge. cfgtest 157/157 with the JUMP key mirrored verbatim.

## REAL HARDWARE (A1200 + PiStorm32/CM4, 14.8.26, 84x54 window,
## REPS 3 SCALE 8 SYNC, driven end-to-end over wasabi)

1.2.7 baseline (S:cb-127-s8.txt):
  TOTAL 19.10s; sync-line 7.04 (4.4ms/line), sgr-colour 2.16,
  plain-lines 1.74, bytewise 1.50, vt-frame 1.10, block-4k 1.04,
  wrap-long 1.00, scroll-nl 0.84, clear-page 0.84.

1.2.8b1 regression, JUMP unset (S:cb-128-s8.txt): TOTAL 19.16,
sync-line 7.04 - identical to 1.2.7 to the hundredth. The knob off
IS the old handler.

1.2.8b1 JUMP8, same window/spec (S:cb-128-j8.txt):
  sync-line  7.04 -> 1.50   (4.7x - 4.4ms/line -> 0.94ms/line)
  plain-lines 1.74 -> 1.50, wrap-long 1.02 -> 0.86,
  bytewise 1.50 -> 1.38; every other row unchanged (sgr-colour
  2.16->2.18 = rep noise; cursor/vt-frame/insdel/clear exactly flat,
  as designed - jumpok() never fires without a bottom-margin LF).
  TOTAL 19.16 -> 13.02 = 32% off the whole honest SYNC suite from
  one opt-in knob.
The residual 0.94ms/line on sync-line = text + packet + WAIT_CHAR
answer + blit/8: the scroll term went from ~3.5ms to ~0.45ms.

1.2.8b1 JUMP32 (S:cb-128-j32.txt): sync-line 0.64 (11.0x vs the
7.04 baseline - 0.40ms/line), plain-lines 1.30, TOTAL 11.52 (40%
off). The knee: JUMP8 already buys 4.7x on sync-line; 32 approaches
the no-blit floor (text + packet + WAIT_CHAR = ~0.4ms/line). On a
54-row window JUMP32 means the cursor rides the bottom 22 rows -
a taste question, the numbers just say what each taste costs.

Stock CON:, same window/spec (S:cb-con-s8.txt): TOTAL 139.16.
plain-lines 29.30, block-4k 28.52, block-32k 28.86, wrap 17.26,
sgr-colour 13.34, sync-line 7.12, bytewise 3.44, clear-page 2.36.

## THE J1 SCOREBOARD (84x54, REPS 3 SCALE 8, SYNC ON, real A1200
## + PiStorm32, all four runs same boot, driven over wasabi)

              CON:     CCON      CCON      CCON
                       (off)     JUMP8     JUMP32
  TOTAL      139.16    19.16     13.02     11.52
  sync-line    7.12     7.04      1.50      0.64

CCON overall: 7.3x faster than stock with JUMP off, 10.7x at JUMP8,
12.1x at JUMP32 - under the barrier mode where every number is
honest. sync-line, the row that tied 0.54=0.54 in the 1.2.4 campaign
and was called "the true remaining hardware gap ... a future
campaign if anyone cares": stock 7.12, CCON JUMP8 1.50 (4.7x),
JUMP32 0.64 (11x). Rows: 14/15 clear wins at JUMP8; insdel-line
0.08? vs 0.14? is stock's known SYNC-piercing console.device
deferral on a sub-threshold row, not a render loss.

Files on the Amiga: S:cb-{127,127-s8,128-s8,128-j8,128-j32,con-s8}
.txt; scripts S:cb*. Local copies in the session scratchpad; the
numbers above are transcribed verbatim.

Next candidates if the campaign continues (from the same doc read):
- E6 extent-narrowed blits: clip the scroll region to the used
  column extent (mask discipline, area axis) - invisible, helps
  real dir/list traffic, does nothing for conbench's 78-char lines.
- The ScrollVPort idea: on an OWN screen, scroll = bitplane-pointer
  arithmetic (the copper doc's zero-cost scroll made OS-legal via
  RyOffset panning + amortized reset blit). Would delete the scroll
  blit entirely; a screen-mode feature, not a window tweak.

14.8.26, after his go: JUMP=8 uncommented in the machine's
L:ccon.cfg (one-line delta against the shipped example, put over
wasabi - per-window read, no reboot). Verified by a plain-window
run (NO JUMP in the open string): sync-line 1.48 / TOTAL 12.96
(S:cb-128-cfg.txt) = the JUMP8 numbers, from the file alone.
Campaign committed as AmigaTools de287ae.
