-> pkcost.e - what one request costs a console, in raw mode, per kind:
-> a 1-byte Write, a WaitForChar with nothing waiting, CSI 6n with its
-> answer read back (conbench's query-cursor), and a 1-byte Read of a
-> byte already waiting. Microseconds each (timer.device's EClock).
-> Run in the console under test: pkcost [N] [TO file]  (default 400;
-> the line of results is also appended to file - never redirect
-> stdout: the requests must reach the console)
-> Written for 1.3.1b4: conbench 0.4 found the stock CON: faster at
-> query-cursor, mode-switch and insdel-line.

MODULE 'dos/dos', 'devices/timer', 'timer'

DEF tio:PTR TO timerequest, freqk

PROC now()
  DEF ev[2]:ARRAY OF LONG
  ReadEClock(ev)
ENDPROC ev[1]

PROC us(t0, t1, n) IS Div(Mul(Div(t1 - t0, n), 1000), freqk)

PROC main()
  DEF in, out, n=400, i, t0, t1, b[16]:ARRAY OF CHAR, k, args:PTR TO LONG, rd,
      r1, r2, r3, r4, r5, r6, r7, fname=NIL, fh, line[200]:STRING, gone=FALSE
  args := [0, 0]:LONG
  rd := ReadArgs('N/N,TO/K', args, NIL)
  IF rd
    IF args[0] THEN n := Long(args[0])
    IF args[1] THEN fname := args[1]
  ENDIF
  tio := New(SIZEOF timerequest)
  IF OpenDevice('timer.device', UNIT_ECLOCK, tio, 0) <> 0 THEN RETURN 20
  timerbase := Long(tio + 20)
  freqk := Div(ReadEClock(b) + 500, 1000)
  in := Input()
  out := Output()
  SetMode(in, 1)
  t0 := now()
  FOR i := 1 TO n DO Write(out, 'x', 1)
  t1 := now()
  r1 := us(t0, t1, n)
  WaitForChar(out, 0)
  t0 := now()
  FOR i := 1 TO n DO WaitForChar(in, 0)
  t1 := now()
  r2 := us(t0, t1, n)
  t0 := now()
  FOR i := 1 TO n
    Write(out, [27,"[","6","n"]:CHAR, 4)
    REPEAT
      IF WaitForChar(in, 500000) = 0
        gone := TRUE            -> no answer: stop, never Read blind
        k := 0
      ELSE
        k := Read(in, b, 1)
      ENDIF
    UNTIL (k <> 1) OR (b[0] = "R")
    EXIT gone
  ENDFOR
  t1 := now()
  r3 := us(t0, t1, n)
  -> answers already waiting: ask 20, then read them byte by byte
  FOR i := 1 TO 20 DO Write(out, [27,"[","6","n"]:CHAR, 4)
  WaitForChar(in, 500000)
  Delay(10)
  k := 0
  t0 := now()
  WHILE WaitForChar(in, 0)
    Read(in, b, 1)
    k++
  ENDWHILE
  t1 := now()
  r4 := IF k > 0 THEN us(t0, t1, k) ELSE 0
  -> mode switches
  t0 := now()
  FOR i := 1 TO n
    SetMode(in, 0)
    SetMode(in, 1)
  ENDFOR
  t1 := now()
  r5 := us(t0, t1, n)
  SetMode(in, 0)
  -> 13-byte writes, drawing included (a barrier at the end): plain text
  -> against conbench insdel-line's CSI r;1H CSI L CSI M
  WriteF('\c[H\c[J', 27, 27)
  WaitForChar(out, 0)
  t0 := now()
  FOR i := 1 TO n DO Write(out, 'abcdefghijklm', 13)
  WaitForChar(out, 0)
  t1 := now()
  r6 := us(t0, t1, n)
  WriteF('\c[H\c[J', 27, 27)
  WaitForChar(out, 0)
  t0 := now()
  FOR i := 1 TO n DO Write(out, [27,"[","1","2",";","1","H",27,"[","L",27,"[","M"]:CHAR, 13)
  WaitForChar(out, 0)
  t1 := now()
  r7 := us(t0, t1, n)
  StringF(line, 'write1 \d us, waitchar \d us, query \d us\s, read-waiting \d us (\d bytes), modeswitch \d us, text13 \d us, insdel13 \d us\n',
          r1, r2, r3, IF gone THEN ' (NO ANSWER)' ELSE '', r4, k, r5, r6, r7)
  WriteF('\n\s', line)
  IF fname
    fh := Open(fname, MODE_READWRITE)
    IF fh = NIL THEN fh := Open(fname, MODE_NEWFILE) ELSE Seek(fh, 0, OFFSET_END)
    IF fh
      Write(fh, line, StrLen(line))
      Close(fh)
    ENDIF
  ENDIF
  IF rd THEN FreeArgs(rd)
  CloseDevice(tio)
ENDPROC
