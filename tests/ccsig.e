-> ccsig.e - ACTION_CHANGE_SIGNAL and the Ctrl+C pair (Audit9 K1, K2,
-> K11, K12; Audit9 T4: no test covered CHANGE_SIGNAL).
->
-> Run it FROM A CCON: SHELL. It talks to the console behind Output():
->
->  1. query (arg2 = 0): res1 must be DOSTRUE, res2 a message port or 0
->     (K12: never a bare task)
->  2. point the break at this process's own pr_MsgPort, passing the
->     handle's fh_Arg1 as arg1 (K11), then query: res2 must be that port
->  3. start a SECOND process that writes to the same console (Run Echo)
->     and ends; then press Ctrl+C within 10 s. The break must arrive
->     here: a writer no longer takes it from a CHANGE_SIGNAL target
->     (K2), and the finished writer is never signalled (K1)
->  4. put the old target back
->
-> Prints PASS or FAIL per step. Stock CON: passes 1, 2 and 4 too.
->
-> Build: ecompile ccsig.e ccsig      (small model is fine)
-> Run on the Amiga, FROM A CCON: SHELL: ccsig

MODULE 'dos/dos', 'dos/dosextens', 'exec/ports', 'exec/nodes',
       'exec/tasks'


PROC main()
  DEF fh:PTR TO filehandle, port, a1, res1, res2, old, me, i, got=FALSE,
      n:PTR TO ln, fails=0
  fh := Shl(Output(), 2)
  IF fh = NIL
    WriteF('no output handle\n')
    RETURN 20
  ENDIF
  port := fh.type               -> the handler's port
  a1 := fh.args                 -> what the handler put in fh_Arg1
  me := FindTask(NIL) + 92      -> our pr_MsgPort (sizeof(struct Task))

  -> 1. query
  res1 := DoPkt(port, ACTION_CHANGE_SIGNAL, a1, 0, 0, 0, 0)
  res2 := IoErr()
  old := res2
  WriteF('1. query: res1=\d res2=$\h\n', res1, res2)
  IF res1 = 0
    WriteF('   FAIL: res1 is not DOSTRUE\n')
    fails++
  ELSEIF res2
    -> a port, not a task: a process's own pr_MsgPort has ln_Type 0
    -> on 3.2, so the test is "not NT_TASK/NT_PROCESS"
    n := res2
    IF (n.type = NT_TASK) OR (n.type = NT_PROCESS)
      WriteF('   FAIL: res2 is a task, not a port (ln_Type \d)\n', n.type)
      fails++
    ELSE
      WriteF('   PASS: res2 is a port (ln_Type \d\s)\n', n.type,
             IF res2 = me THEN ', our own pr_MsgPort' ELSE '')
    ENDIF
  ELSE
    WriteF('   PASS: res2 is 0 (no target yet)\n')
  ENDIF

  -> 2. set to our own port, then query
  res1 := DoPkt(port, ACTION_CHANGE_SIGNAL, a1, me, 0, 0, 0)
  res1 := DoPkt(port, ACTION_CHANGE_SIGNAL, a1, 0, 0, 0, 0)
  res2 := IoErr()
  IF res2 = me
    WriteF('2. PASS: the target is our pr_MsgPort ($\h)\n', me)
  ELSE
    WriteF('2. FAIL: res2=$\h, expected $\h\n', res2, me)
    fails++
  ENDIF

  -> 3. another process writes, then Ctrl+C
  SetSignal(0, SIGBREAKF_CTRL_C)
  Execute('Run Echo "   (a second process writes to this console and ends)"', 0, Output())
  Delay(100)
  WriteF('3. press Ctrl+C now (10 s)...\n')
  FOR i := 1 TO 100
    IF SetSignal(0, 0) AND SIGBREAKF_CTRL_C
      got := TRUE
      i := 100
    ELSE
      Delay(5)
    ENDIF
  ENDFOR
  SetSignal(0, SIGBREAKF_CTRL_C)
  IF got
    WriteF('   PASS: the break came here\n')
  ELSE
    WriteF('   FAIL: no break arrived\n')
    fails++
  ENDIF

  -> 4. put the old target back
  res1 := DoPkt(port, ACTION_CHANGE_SIGNAL, a1, IF old THEN old ELSE me, 0, 0, 0)
  WriteF('4. \s: old target restored\n', IF res1 THEN 'PASS' ELSE 'FAIL')
  IF res1 = 0 THEN fails++
  WriteF('\s\n', IF fails = 0 THEN 'ALL PASS' ELSE 'SOME FAILED')
ENDPROC IF fails = 0 THEN 0 ELSE 10
