import React, { useEffect, useRef, useState } from "react";
import { StageEngine, type StageSnapshot } from "../engine/stage";
import { ThreeStageView } from "./ThreeStageView";
import { WebSynth } from "../audio/webSynth";
import { MidiDebugOverlay, type MidiEventInfo } from "./MidiDebugOverlay";

export const TeatroStageApp: React.FC = () => {
  const engineRef = useRef<StageEngine | null>(null);
  const lastTimeRef = useRef<number | null>(null);
  const rafRef = useRef<number | null>(null);
  const synthRef = useRef<WebSynth | null>(null);
  const [snapshot, setSnapshot] = useState<StageSnapshot | null>(null);
  const [isPlaying, setIsPlaying] = useState(true);
  const [windStrength, setWindStrength] = useState(0.6);
  const [audioEnabled, setAudioEnabled] = useState(false);
  const [masterGain, setMasterGain] = useState(0.1);
  const [wave, setWave] = useState<OscillatorType>("sine");
  const [showMidiLog, setShowMidiLog] = useState(false);
  const [midiStatus, setMidiStatus] = useState<{
    supported: boolean;
    state: "pending" | "granted" | "denied" | "unsupported";
    inputs: number;
  }>({ supported: true, state: "pending", inputs: 0 });
  const midiLogRef = useRef<MidiEventInfo[]>([]);
  const [, forceTick] = useState(0);
  const barMotionRef = useRef({
    swayAmp: 2.0,
    swayRate: 0.7,
    upDownAmp: 0.5,
    upDownRate: 0.9
  });

  useEffect(() => {
    engineRef.current = new StageEngine();
    engineRef.current.setWindStrength(windStrength);
    engineRef.current.setBarMotion(barMotionRef.current);
    synthRef.current = new WebSynth();
    synthRef.current.setParams({ masterGain, wave });

    const loop = () => {
      const now = performance.now();
      const last = lastTimeRef.current ?? now;
      const dtSeconds = (now - last) / 1000;
      lastTimeRef.current = now;

      const engine = engineRef.current;
      if (engine && isPlaying) {
        engine.step(dtSeconds);
        setSnapshot(engine.snapshot());
      }

      rafRef.current = requestAnimationFrame(loop);
    };

    rafRef.current = requestAnimationFrame(loop);

    return () => {
      if (rafRef.current != null) {
        cancelAnimationFrame(rafRef.current);
      }
    };
  }, [isPlaying, windStrength, masterGain, wave]);

  const handleTogglePlay = () => {
    setIsPlaying((prev) => !prev);
  };

  const handleWindChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseFloat(e.target.value);
    setWindStrength(value);
    engineRef.current?.setWindStrength(value);
  };

  const handleEnableAudio = () => {
    const synth = synthRef.current;
    if (!synth) return;
    if (!audioEnabled) {
      synth.resume();
      synth.setParams({ masterGain, wave });
      setAudioEnabled(true);
    } else {
      synth.stopAll();
      synth.mute();
      setAudioEnabled(false);
    }
  };

  const handleGainChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseFloat(e.target.value);
    setMasterGain(value);
    if (audioEnabled) {
      synthRef.current?.setParams({ masterGain: value });
    }
  };

  const handleWaveChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
    const value = e.target.value as OscillatorType;
    setWave(value);
    synthRef.current?.setParams({ wave: value });
  };

  // Web MIDI: map CC to stage params if available.
  useEffect(() => {
    if (!("requestMIDIAccess" in navigator)) {
      setMidiStatus({ supported: false, state: "unsupported", inputs: 0 });
      return;
    }
    let access: WebMidi.MIDIAccess | null = null;
    const onMIDIMessage = (e: WebMidi.MIDIMessageEvent) => {
      const [status, data1, data2] = e.data;
      const cmd = status & 0xf0;
      const isCC = (status & 0xf0) === 0xb0;
      const isNoteOn = cmd === 0x90 && data2 > 0;
      const isNoteOff = cmd === 0x80 || (cmd === 0x90 && data2 === 0);

      const type: MidiEventInfo["type"] = isNoteOn
        ? "noteon"
        : isNoteOff
        ? "noteoff"
        : isCC
        ? "cc"
        : "other";
      midiLogRef.current = [
        { ts: performance.now() / 1000, status, data1, data2: data2 ?? 0, type },
        ...midiLogRef.current
      ].slice(0, 50);
      forceTick((x) => x + 1);

      if (!isCC) {
        if (isNoteOn) synthRef.current?.noteOn(data1, data2 ?? 100);
        else if (isNoteOff) synthRef.current?.noteOff(data1);
        return;
      }
      const cc = data1;
      const val = data2 ?? 0;
      const norm = val / 127;
      if (cc === 1) {
        const w = 1.5 * norm;
        setWindStrength(w);
        engineRef.current?.setWindStrength(w);
        synthRef.current?.setParams({ masterGain: 0.05 + 0.15 * norm });
      } else if (cc === 2) {
        barMotionRef.current = { ...barMotionRef.current, swayAmp: 4 * norm };
        engineRef.current?.setBarMotion({ swayAmp: 4 * norm });
      } else if (cc === 3) {
        barMotionRef.current = { ...barMotionRef.current, upDownAmp: 2 * norm };
        engineRef.current?.setBarMotion({ upDownAmp: 2 * norm });
      } else if (cc === 4) {
        barMotionRef.current = { ...barMotionRef.current, swayRate: 1.5 * norm };
        engineRef.current?.setBarMotion({ swayRate: 1.5 * norm });
      } else if (cc === 5) {
        // Change waveform (coarse): 0..0.49 => sine, 0.5..0.99 => triangle
        const w: OscillatorType = norm < 0.5 ? "sine" : "triangle";
        synthRef.current?.setParams({ wave: w });
      }
    };

    if ("requestMIDIAccess" in navigator) {
      (navigator as any)
        .requestMIDIAccess()
        .then((a: WebMidi.MIDIAccess) => {
          access = a;
          setMidiStatus({ supported: true, state: "granted", inputs: a.inputs.size });
          access.inputs.forEach((input) => {
            input.addEventListener("midimessage", onMIDIMessage as any);
          });
          access.onstatechange = () => {
            setMidiStatus({
              supported: true,
              state: "granted",
              inputs: access ? access.inputs.size : 0
            });
            access?.inputs.forEach((input) => {
              input.removeEventListener("midimessage", onMIDIMessage as any);
              input.addEventListener("midimessage", onMIDIMessage as any);
            });
          };
        })
        .catch(() => {
          setMidiStatus({ supported: true, state: "denied", inputs: 0 });
        });
    }

    return () => {
      if (access) {
        access.inputs.forEach((input) => {
          input.removeEventListener("midimessage", onMIDIMessage as any);
        });
      }
    };
  }, []);

  const timeSeconds = snapshot?.time ?? 0;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        backgroundColor: "#f4ead6"
      }}
    >
      <header
        style={{
          padding: "8px 12px",
          fontFamily:
            "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
          fontSize: 14,
          fontWeight: 500,
          borderBottom: "1px solid rgba(0,0,0,0.08)"
        }}
      >
        <span>Teatro Stage Engine — Web (rebuild in progress)</span>
        <span style={{ marginLeft: 16, opacity: 0.7 }}>
          t = {timeSeconds.toFixed(2)}s · {isPlaying ? "playing" : "paused"}
        </span>
      </header>
      <main style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, position: "relative" }}>
          {snapshot && <ThreeStageView snapshot={snapshot} />}
          <div
            style={{
              position: "absolute",
              left: 12,
              bottom: 12,
              display: "inline-flex",
              alignItems: "center",
              gap: 10,
              padding: "6px 10px",
              borderRadius: 10,
              backgroundColor: "rgba(244, 234, 214, 0.9)",
        border: "1px solid rgba(0,0,0,0.12)",
          fontSize: 12,
          fontFamily:
            "system-ui, -apple-system, BlinkMacSystemFont, sans-serif",
          fontVariantNumeric: "tabular-nums"
        }}
          >
            <button
              type="button"
              onClick={handleTogglePlay}
              style={{
                border: "none",
                background: "transparent",
                padding: "2px 6px",
              cursor: "pointer",
              fontSize: 12
            }}
          >
              {isPlaying ? "Pause" : "Play"}
            </button>
            <span
              style={{
                opacity: 0.7,
                minWidth: 68,
                textAlign: "right",
                display: "inline-block"
              }}
            >
              t = {timeSeconds.toFixed(2)}s
            </span>
            <span style={{ opacity: 0.7, minWidth: 100 }}>
              MIDI: {midiStatus.state} ({midiStatus.inputs})
            </span>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              wind
              <input
                type="range"
                min="0"
                max="1.5"
                step="0.05"
                value={windStrength}
                onChange={handleWindChange}
              />
              <span style={{ width: 36, textAlign: "right" }}>
                {windStrength.toFixed(2)}
              </span>
            </label>
            <button
              type="button"
              onClick={handleEnableAudio}
              style={{
                border: "1px solid rgba(0,0,0,0.2)",
                borderRadius: 6,
                background: audioEnabled ? "rgba(0,0,0,0.1)" : "transparent",
                padding: "2px 8px",
                cursor: "pointer",
                fontSize: 12
              }}
            >
              {audioEnabled ? "Audio on" : "Audio off"}
            </button>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              gain
              <input
                type="range"
                min="0"
                max="0.5"
                step="0.01"
                value={masterGain}
                onChange={handleGainChange}
                disabled={!audioEnabled}
              />
              <span style={{ width: 36, textAlign: "right" }}>
                {masterGain.toFixed(2)}
              </span>
            </label>
            <label style={{ display: "inline-flex", alignItems: "center", gap: 4 }}>
              wave
              <select value={wave} onChange={handleWaveChange} disabled={!audioEnabled} style={{ fontSize: 12 }}>
                <option value="sine">sine</option>
                <option value="triangle">triangle</option>
              </select>
            </label>
            <button
              type="button"
              onClick={() => synthRef.current?.testNote()}
              disabled={!audioEnabled}
              style={{
                border: "1px solid rgba(0,0,0,0.2)",
                borderRadius: 6,
                background: "transparent",
                padding: "2px 8px",
                cursor: audioEnabled ? "pointer" : "not-allowed",
                fontSize: 12
              }}
            >
              Test tone
            </button>
            <button
              type="button"
              onClick={() => setShowMidiLog((v) => !v)}
              style={{
                border: "1px solid rgba(0,0,0,0.2)",
                borderRadius: 6,
                background: "transparent",
                padding: "2px 8px",
                cursor: "pointer",
                fontSize: 12
              }}
            >
              {showMidiLog ? "Hide MIDI" : "Show MIDI"}
            </button>
          </div>
          <MidiDebugOverlay
            events={midiLogRef.current}
            visible={showMidiLog}
            onClear={() => {
              midiLogRef.current = [];
              forceTick((x) => x + 1);
            }}
          />
        </div>
      </main>
    </div>
  );
};
