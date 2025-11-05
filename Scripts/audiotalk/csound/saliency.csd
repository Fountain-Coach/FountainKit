<CsoundSynthesizer>
<CsOptions>
; Realtime audio out; CoreAudio on macOS
-odac -d
</CsOptions>
<CsInstruments>
sr      = 48000
ksmps   = 64
nchnls  = 2
0dbfs   = 1

giMidiChan init 1

instr 1
  ; Simple sine/tri blend driven by MIDI note/vel and CC1 (mod)
  inote   notnum
  ivel    veloc 0, 127
  kvel    = ivel/127
  ; CC1 (mod wheel) captured via chnget when routed by host; default 0
  kmod    chnget "mod1"
  ; Map note to freq
  kcps    cpsmidinn inote
  ; Envelope quick attack/decay
  aenv    madsr 0.005, 0.05, 0.6, 0.1
  ; Osc mix controlled by mod
  as     oscili aenv*kvel*(1-kmod), kcps, 1
  at     vco2   aenv*kvel*kmod, kcps, 12
  aL     = (as + at)*0.5
  aR     = aL
  outs aL, aR
endin

; MIDI routing
instr 98
  ; Capture CC1 into channel "mod1" for instrument 1
  kch, kctrl, kval midictrl
  if (kctrl == 1) then
    kval = kval/127
    chnset kval, "mod1"
  endif
endin

</CsInstruments>
<CsScore>
; preload sine table
f 1 0 16384 10 1
; Always-on controller listener
i 98 0 3600
</CsScore>
</CsoundSynthesizer>

