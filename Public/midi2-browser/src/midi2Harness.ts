import {
  encodeNoteOn,
  encodeNoteOff,
  encodeProgramChange,
  Midi2Scheduler,
  createBrowserClock
} from '@fountain-coach/midi2'

export type UmpEvent = { ts: number; bytes: number[]; label: string }

export function makeHarness() {
  const events: UmpEvent[] = []
  const clock = createBrowserClock()
  const scheduler = new Midi2Scheduler(clock)

  const record = (label: string, data: number[]) => {
    events.push({ ts: Date.now(), bytes: data, label })
    if (events.length > 200) events.shift()
  }

  const noteOn = (group: number, channel: number, note: number, velocity: number) => {
    const msg = encodeNoteOn({ group, channel, note, velocity })
    record('noteOn', msg)
    return msg
  }

  const noteOff = (group: number, channel: number, note: number, velocity: number) => {
    const msg = encodeNoteOff({ group, channel, note, velocity })
    record('noteOff', msg)
    return msg
  }

  const programChange = (group: number, channel: number, program: number) => {
    const msg = encodeProgramChange({ group, channel, program })
    record('programChange', msg)
    return msg
  }

  return {
    clock,
    scheduler,
    events,
    noteOn,
    noteOff,
    programChange
  }
}
