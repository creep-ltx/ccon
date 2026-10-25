| engine.bin's entry table: the handler calls offset 0 (frun), 4 (fcheck),
| 8 (ppaint), 12 (gshift), 16 (wacc), 20 (cflush), 24 (cfout_e), 28 (wchar), 32 (rdacc,
| 1.3.1b4; was drain until Audit8 J31), 36 (mscan)
	.text
	.globl _start
_start:
	bra.w	frun
	bra.w	fcheck
	bra.w	ppaint
	bra.w	gshift
	bra.w	wacc
	bra.w	cflush
	bra.w	cfout_e
	bra.w	wchar
	bra.w	rdacc		| 32: 1.3.1b4 (was drain, removed by Audit8 J31)
	bra.w	mscan
