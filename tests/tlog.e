-> tlog: log the strings drawn through graphics.library Text() until Ctrl-C
MODULE 'dos/dos'

PROC main()
  DEF old, b:PTR TO CHAR, n, i, l
  b := New(4096)
  PutLong({buf}, b)
  old := SetFunction(gfxbase, -60, {patch})
  PutLong({oldp}, old)
  Wait(SIGBREAKF_CTRL_C)
  SetFunction(gfxbase, -60, old)
  n := Long({pos})
  i := 0
  WHILE i < n
    l := b[i]
    WriteF('[')
    Write(stdout, b + i + 1, l)
    WriteF(']\n')
    i := i + l + 1
  ENDWHILE
ENDPROC

-> each call appends: one length byte, then up to 60 chars
patch:
  MOVEM.L D0-D2/A0-A2,-(A7)
  LEA pos(PC),A2
  MOVE.L (A2),D1
  CMP.L #4000,D1
  BHI.S pdone
  CMP.L #60,D0
  BLS.S pok
  MOVEQ #60,D0
pok:
  MOVE.L buf(PC),A1
  ADDA.L D1,A1
  MOVE.B D0,(A1)+
  ADDQ.L #1,D1
  ADD.L D0,D1
  MOVE.L D1,(A2)
  SUBQ.L #1,D0
  BMI.S pdone
pcp:
  MOVE.B (A0)+,(A1)+
  DBRA D0,pcp
pdone:
  MOVEM.L (A7)+,D0-D2/A0-A2
  MOVE.L oldp(PC),-(A7)
  RTS
pos:
  LONG 0
buf:
  LONG 0
oldp:
  LONG 0
