<CsoundSynthesizer>
<CsOptions>
; Realtime audio out (device will be selected by runner)
-odac -d
</CsOptions>
<CsInstruments>
sr      = 48000
ksmps   = 64
nchnls  = 2
0dbfs   = 1

giMidiChan init 1

instr 1
  ; Continuous engine; amplitude follows CC1 (saliency). No auto turnoff.
  kmod    chnget "mod1"
  kamp    = kmod
  kcps    = cpsmidinn(60 + (kmod * 12))
  as      oscili kamp, kcps, 1
  outs as, as
endin

; MIDI routing
instr 98
  ; Poll CC1 (mod wheel) on channel 1 and map to 0..1, then expose via chnset
  kval ctrl7 1, 1, 0, 1
  chnset kval, "mod1"
endin

</CsInstruments>
<CsScore>
; preload sine table
f 1 0 16384 10 1
; Always-on controller listener
i 98 0 3600
; Always-on instrument for continuous synthesis
i 1 0 3600
</CsScore>
</CsoundSynthesizer>
