-> rawdump.e - what does a RAW reader get from the console? Sets the
-> console raw, reads everything that arrives for SECS seconds (default
-> 15) one byte at a time, as a raw line editor does, and writes it to
-> FILE. Then cooked again. Used to tell a console's paste cut from a
-> shell's (1.3.1b2: a csh paste was cut mid-line - whose cut?).
->
-> Build: ecompile rawdump.e rawdump
-> Run in the console under test: rawdump RAM:raw.bin 15, then paste.

MODULE 'dos/dos'

PROC main()
  DEF args:PTR TO LONG, rd, fh, in, b[4]:ARRAY OF CHAR, n, secs=15, got=0, t
  args := [NIL, NIL]
  rd := ReadArgs('FILE/A,SECS/N', args, NIL)
  IF rd = NIL
    WriteF('usage: rawdump FILE [SECS]\n')
    RETURN 20
  ENDIF
  IF args[1] THEN secs := Long(args[1])
  fh := Open(args[0], MODE_NEWFILE)
  IF fh = NIL
    FreeArgs(rd)
    RETURN 20
  ENDIF
  in := Input()
  WriteF('rawdump: \d s, paste now\n', secs)
  SetMode(in, 1)
  t := Mul(secs, 10)            -> tenths of a second without input
  WHILE t > 0
    IF WaitForChar(in, 100000)
      n := Read(in, b, 1)
      IF n = 1
        Write(fh, b, 1)
        got++
      ENDIF
    ELSE
      t--
    ENDIF
  ENDWHILE
  SetMode(in, 0)
  Close(fh)
  FreeArgs(rd)
  WriteF('rawdump: \d bytes\n', got)
ENDPROC
