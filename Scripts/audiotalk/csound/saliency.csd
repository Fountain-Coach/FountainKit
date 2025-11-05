<CsoundSynthesizer>
<CsOptions>
; Realtime audio out; CoreAudio on macOS; enable CoreMIDI and open all MIDI inputs
-odac -d -Ma -+rtmidi=CoreMIDI
</CsOptions>
<CsInstruments>
sr      = 48000
ksmps   = 64
nchnls  = 2
0dbfs   = 1

giMidiChan init 1

instr 1
  ; Continuous sonification driven by CC1 (mod), no MIDI notes required
  kmod    chnget "mod1"         ; 0..1 saliency
  kamp    = 0.12 + 0.28*kmod     ; output level
  kcps    = cpsmidinn(60 + (kmod * 12)) ; sweep one octave above middle C
  as      oscili kamp*(1-kmod), kcps, 1   ; sine
  at      lfo    kamp*kmod, kcps, 0       ; triangle
  aL      = (as + at)*0.5
  outs aL, aL
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
