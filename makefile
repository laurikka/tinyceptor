all: tinyceptor.prg

tinyceptor.prg: tinyceptor.s
		vasm6502_oldstyle -Fbin -cbm-prg -illegal -DSTANDALONE=1 tinyceptor.s -o tinyceptor.prg
		vasm6502_oldstyle -Fbin -illegal -DSTANDALONE=0 -DSIDHEADER=1 tinyceptor.s -o tinyceptor.sid
		vasm6502_oldstyle -Fbin -illegal -DSTANDALONE=0 -DSIDHEADER=0 tinyceptor.s -o tinyceptor_music.bin
#		c1541 -format tinyceptor,01 d64 tinyceptor.d64 -attach tinyceptor.d64 -write tinyceptor.prg tinyceptor
#		denise tinyceptor.prg
#		retrodebugger tinyceptor.prg
#		vsid tinyceptor.sid