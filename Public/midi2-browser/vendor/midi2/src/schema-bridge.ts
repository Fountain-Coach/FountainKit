import {
  Flex_Lyric,
  Flex_Tempo,
  Flex_KeySignature,
  Flex_TimeSignature,
  UmpPacket,
  UmpPacket32,
  UmpPacket64,
  UmpPacket128,
  isUmpPacket,
  StreamBody,
  isStreamBody,
} from "./generated/openapi-types";
import {
  MidiCiEvent,
  SysEx7Event,
  SysEx8Event,
  Midi1ChannelVoiceEvent,
  Midi2ChannelPressureEvent,
  Midi2ControlChangeEvent,
  Midi2Event,
  Midi2NoteOffEvent,
  Midi2NoteOnEvent,
  Midi2NrpnEvent,
  Midi2NrpnRelativeEvent,
  Midi2PerNoteAssignableControllerEvent,
  Midi2PerNoteManagementEvent,
  Midi2PerNoteRegisteredControllerEvent,
  Midi2PitchBendEvent,
  Midi2PolyPressureEvent,
  Midi2ProgramChangeEvent,
  Midi2RpnEvent,
  Midi2RpnRelativeEvent,
  Midi2SystemEvent,
  UtilityEvent,
  FlexTempoEvent,
  FlexTimeSignatureEvent,
  FlexKeySignatureEvent,
  FlexLyricEvent,
  StreamEvent,
  ProfileEvent,
  PropertyExchangeEvent,
  ProcessInquiryEvent,
} from "./types";
import { encodeUmp, decodeUmp } from "./ump";
import { fragmentSysEx7, fragmentSysEx8 } from "./sysex";
import { decodeMidiCiFromSysEx } from "./midici";

type ScopeAddress = { scope: "group"; group: number } | { scope: "channel"; channel: number };
const STREAM_MT = 0xf;
const STREAM_OPCODE_ENDPOINT = 0x00;
const STREAM_OPCODE_CONFIG = 0x01;
const STREAM_OPCODE_FUNCTION_BLOCK = 0x02;
const STREAM_OPCODE_PROCESS_INQUIRY = 0x03;

function toAddress(group: number, channel?: number): ScopeAddress | undefined {
  if (channel === undefined) return { scope: "group", group };
  return { scope: "channel", channel };
}

function asUmpPacket64(event: Midi2Event): UmpPacket64 | null {
  switch (event.kind) {
    case "sysex7":
    case "sysex8":
    case "midiCi":
      return null; // handled in 32/128-bit paths
    case "noteOn": {
      const body: Midi2NoteOnEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 9,
        channel: body.channel,
        body: {
          statusNibble: 9,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            velocity16: body.velocity,
            attributeType: body.attributeType ?? 0,
            attributeData16: body.attributeData ?? 0,
          },
        },
      };
    }
    case "noteOff": {
      const body: Midi2NoteOffEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 8,
        channel: body.channel,
        body: {
          statusNibble: 8,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            velocity16: body.velocity ?? 0,
            attributeType: body.attributeType ?? 0,
            attributeData16: body.attributeData ?? 0,
          },
        },
      };
    }
    case "polyPressure": {
      const body: Midi2PolyPressureEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 10,
        channel: body.channel,
        body: {
          statusNibble: 10,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            polyPressure32: body.pressure,
          },
        },
      };
    }
    case "controlChange": {
      const body: Midi2ControlChangeEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 11,
        channel: body.channel,
        body: {
          statusNibble: 11,
          channel: body.channel,
          body: {
            control: body.controller,
            controlValue32: body.value,
          },
        },
      };
    }
    case "programChange": {
      const body: Midi2ProgramChangeEvent = event;
      const bankValid = body.bankLsb !== undefined || body.bankMsb !== undefined;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 12,
        channel: body.channel,
        body: {
          statusNibble: 12,
          channel: body.channel,
          body: {
            program: body.program,
            bankMsb: body.bankMsb,
            bankLsb: body.bankLsb,
            bankValid,
          },
        },
      };
    }
    case "channelPressure": {
      const body: Midi2ChannelPressureEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 13,
        channel: body.channel,
        body: {
          statusNibble: 13,
          channel: body.channel,
          body: {
            channelPressure32: body.pressure,
          },
        },
      };
    }
    case "pitchBend": {
      const body: Midi2PitchBendEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 14,
        channel: body.channel,
        body: {
          statusNibble: 14,
          channel: body.channel,
          body: {
            pitchBend32: body.value,
          },
        },
      };
    }
    case "rpn": {
      const body: Midi2RpnEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            rpnIndexMsb: body.bank,
            rpnIndexLsb: body.index,
            rpnData32: body.value,
          },
        },
      };
    }
    case "nrpn": {
      const body: Midi2NrpnEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            nrpnIndexMsb: body.bank,
            nrpnIndexLsb: body.index,
            nrpnData32: body.value,
          },
        },
      };
    }
    case "rpnRelative": {
      const body: Midi2RpnRelativeEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            rpnIndexMsb: body.bank,
            rpnIndexLsb: body.index,
            rpnDelta32: body.delta,
          },
        },
      };
    }
    case "nrpnRelative": {
      const body: Midi2NrpnRelativeEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            nrpnIndexMsb: body.bank,
            nrpnIndexLsb: body.index,
            nrpnDelta32: body.delta,
          },
        },
      };
    }
    case "perNoteManagement": {
      const body: Midi2PerNoteManagementEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            detach: body.detach,
            reset: body.reset,
          },
        },
      };
    }
    case "perNoteRegisteredController": {
      const body: Midi2PerNoteRegisteredControllerEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            regPerNoteCtrlIndex: body.controller,
            regPerNoteCtrlValue32: body.value,
          },
        },
      };
    }
    case "perNoteAssignableController": {
      const body: Midi2PerNoteAssignableControllerEvent = event;
      return {
        messageType: 4,
        group: body.group,
        statusNibble: 15,
        channel: body.channel,
        body: {
          statusNibble: 15,
          channel: body.channel,
          body: {
            noteNumber: body.note,
            assignPerNoteCtrlIndex: body.controller,
            assignPerNoteCtrlValue32: body.value,
          },
        },
      };
    }
    default:
      return null;
  }
}

function asUmpPacket128(event: Midi2Event): UmpPacket128 | null {
  switch (event.kind) {
    case "sysex8": {
      const syx: SysEx8Event = event;
      const body: UmpPacket128["body"] = {
        kind: "sysex8",
        sysex8: {
          manufacturerId: syx.manufacturerId,
          length: syx.payload.length,
          data: Array.from(syx.payload),
        },
      };
      return { messageType: 5, group: syx.group, body };
    }
    case "midiCi": {
      if (event.format !== "sysex8") return null;
      const scope = event.scope === "realtime" ? 0x7f : 0x7e;
      const header = [scope, 0x0d, event.subId2, event.version];
      const syx: SysEx8Event = {
        kind: "sysex8",
        group: event.group,
        manufacturerId: [scope],
        payload: Uint8Array.from([...header, ...event.payload]),
      };
      return asUmpPacket128(syx);
    }
    case "flexTempo": {
      const flex: FlexTempoEvent = event;
      const body: Flex_Tempo = {
        statusClass: 16,
        status: 1,
        address: toAddress(flex.group, flex.channel),
        data: { bpm: flex.bpm },
      };
      return { messageType: 13, group: flex.group, body };
    }
    case "flexTimeSignature": {
      const flex: FlexTimeSignatureEvent = event;
      const body: Flex_TimeSignature = {
        statusClass: 16,
        status: 2,
        address: toAddress(flex.group, flex.channel),
        data: { numerator: flex.numerator, denominatorPow2: flex.denominatorPow2 },
      };
      return { messageType: 13, group: flex.group, body };
    }
    case "flexKeySignature": {
      const flex: FlexKeySignatureEvent = event;
      const body: Flex_KeySignature = {
        statusClass: 16,
        status: 4,
        address: toAddress(flex.group, flex.channel),
        data: { key: flex.key },
      };
      return { messageType: 13, group: flex.group, body };
    }
    case "flexLyric": {
      const flex: FlexLyricEvent = event;
      const body: Flex_Lyric = {
        statusClass: 17,
        status: 2,
        address: toAddress(flex.group, flex.channel),
        data: { lyric: flex.text },
      };
      return { messageType: 13, group: flex.group, body };
    }
    default:
      return null;
  }
}

function asUmpPacket32(event: Midi2Event): UmpPacket32 | null {
  switch (event.kind) {
    case "sysex7": {
      const syx: SysEx7Event = event;
      const packets = sysex7ToPackets(Array.from(syx.payload));
      return { messageType: 3, group: syx.group, body: { manufacturerId: syx.manufacturerId, packets } };
    }
    case "stream": {
      const stream: StreamEvent = event;
      const body = streamBodyFromEvent(stream);
      return { messageType: STREAM_MT, group: stream.group, body } as unknown as UmpPacket32;
    }
    case "midiCi": {
      if (event.format === "sysex8") return null;
      const scope = event.scope === "realtime" ? 0x7f : 0x7e;
      const header = [scope, 0x0d, event.subId2 & 0x7f, event.version & 0x7f];
      const body = sysEx7BodyFromPayload([scope], Uint8Array.from([...header, ...event.payload]));
      return { messageType: 3, group: event.group, body } as unknown as UmpPacket32;
    }
    case "profile": {
      const p: ProfileEvent = event;
      const body = profileToBody(p);
      const scope = 0x7e;
      const header = [scope, 0x0d, 0x20, 0x01];
      const syxBody = sysEx7BodyFromPayload([scope], Uint8Array.from([...header, ...body]));
      return { messageType: 3, group: p.group, body: syxBody } as unknown as UmpPacket32;
    }
    case "processInquiry": {
      const pi: ProcessInquiryEvent = event;
      const body = processInquiryToBody(pi);
      const scope = 0x7e;
      const header = [scope, 0x0d, 0x22, 0x01];
      const syxBody = sysEx7BodyFromPayload([scope], Uint8Array.from([...header, ...body]));
      return { messageType: 3, group: pi.group, body: syxBody } as unknown as UmpPacket32;
    }
    case "propertyExchange": {
      const pe: PropertyExchangeEvent = event;
      const body = propertyExchangeToBody(pe);
      const scope = 0x7e;
      const header = [scope, 0x0d, 0x21, 0x01];
      const syxBody = sysEx7BodyFromPayload([scope], Uint8Array.from([...header, ...body]));
      return { messageType: 3, group: pe.group, body: syxBody } as unknown as UmpPacket32;
    }
    case "utility": {
      const utility: UtilityEvent = event;
      const opcode = utility.status === "jrClock" ? 1 : utility.status === "jrTimestamp" ? 2 : 0;
      const body: UmpPacket32["body"] = {
        opcode,
        jrClock: utility.status === "jrClock" ? { timestamp32: utility.value ?? 0 } : undefined,
        jrTimestamp: utility.status === "jrTimestamp" ? { time15: utility.value ?? 0 } : undefined,
      };
      return { messageType: 0, group: 0, body };
    }
    case "system": {
      const sys: Midi2SystemEvent = event;
      const body: UmpPacket32["body"] = {
        status: sys.status,
        data1: sys.data1,
        data2: sys.data2,
      };
      return { messageType: 1, group: sys.group, body };
    }
    case "midi1ChannelVoice": {
      const m1: Midi1ChannelVoiceEvent = event;
      const statusNibble = (m1.status >> 4) & 0xf;
      const channel = m1.status & 0xf;
      const body: any = { statusNibble, channel };
      if (statusNibble === 8 || statusNibble === 9) {
        body.noteNumber = m1.data1 ?? 0;
        body.velocity7 = m1.data2 ?? 0;
      } else if (statusNibble === 10) {
        body.noteNumber = m1.data1 ?? 0;
        body.pressure7 = m1.data2 ?? 0;
      } else if (statusNibble === 11) {
        body.control = m1.data1 ?? 0;
        body.value7 = m1.data2 ?? 0;
      } else if (statusNibble === 12) {
        body.program = m1.data1 ?? 0;
      } else if (statusNibble === 13) {
        body.pressure7 = m1.data1 ?? 0;
      } else if (statusNibble === 14) {
        const lsb = m1.data1 ?? 0;
        const msb = m1.data2 ?? 0;
        body.pitchBend14 = (msb << 7) | lsb;
      }
      return { messageType: 2, group: m1.group, body };
    }
    default:
      return null;
  }
}

export function eventToSchemaPacket(event: Midi2Event): UmpPacket | null {
  if (event.kind === "rawUMP" && event.words?.length) {
    const mt = (event.words[0] >>> 28) & 0xf;
    if (mt === STREAM_MT) {
      const stream = decodeStreamWord(event.words[0]);
      if (stream) {
        const body = streamBodyFromEvent(stream);
        return { messageType: STREAM_MT, group: stream.group, body } as unknown as UmpPacket32;
      }
    }
  }
  return (asUmpPacket64(event) as UmpPacket | null) ?? (asUmpPacket128(event) as UmpPacket | null) ?? (asUmpPacket32(event) as UmpPacket | null);
}

export function schemaPacketToEvent(packet: unknown): Midi2Event | null {
  if (!isUmpPacket(packet)) {
    if (typeof packet === "object" && packet && ("messageType" in packet)) {
      const mt = (packet as any).messageType;
      if (mt === 3) {
        const body: any = (packet as any).body;
        if (isStreamBody(body)) {
          return streamBodyToEvent((packet as any).group ?? 0, body);
        }
        if (body && typeof body === "object" && "opcode" in body) {
          return streamBodyToEvent((packet as any).group ?? 0, {
            opcode: body.opcode ?? 0,
            endpointDiscovery: body.endpointDiscovery,
            streamConfigRequest: body.streamConfigRequest,
            streamConfigNotification: body.streamConfigNotification,
            functionBlockDiscovery: body.functionBlockDiscovery,
            functionBlockInfo: body.functionBlockInfo,
          } as StreamBody);
        }
        const words = packGeneric32(packet as any);
        const stream = decodeStreamWord(words[0]);
        if (stream) return stream;
        return { kind: "rawUMP", words, timestamp: undefined };
      }
      if (mt === STREAM_MT) {
        const words = packGeneric32(packet as any);
        const stream = decodeStreamWord(words[0]);
        if (stream) return stream;
        return { kind: "rawUMP", words, timestamp: undefined };
      }
    }
    return null;
  }
  if (packet.messageType === 3) {
    const p = packet as UmpPacket32;
    const body: any = p.body;
    if (body?.manufacturerId && body?.packets) {
      const { manufacturerId, payload } = reassembleSysEx7FromPackets(body.manufacturerId ?? [], body.packets);
      const syx: SysEx7Event = {
        kind: "sysex7",
        group: p.group ?? 0,
        manufacturerId,
        payload: Uint8Array.from(payload),
      };
      const maybeCi = decodeMidiCiFromSysEx(syx);
      if (maybeCi) return midiCiToEvent(maybeCi);
      return syx;
    }
    if (isStreamBody(body)) {
      return streamBodyToEvent(p.group ?? 0, body);
    }
    const words = packGeneric32(p);
    return { kind: "rawUMP", words, timestamp: undefined };
  }
  if (packet.messageType === STREAM_MT) {
    const word = packGeneric32(packet as UmpPacket32);
    return decodeStreamWord(word[0]);
  }
  if (packet.messageType === 4) {
    const body = (packet as UmpPacket64).body;
    const status = body?.statusNibble;
    const channel = body?.channel;
    const cv = (body as any)?.body ?? {};
    switch (status) {
      case 8:
        return {
          kind: "noteOff",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          note: cv.noteNumber ?? 0,
          velocity: cv.velocity16 ?? 0,
          attributeType: cv.attributeType,
          attributeData: cv.attributeData16,
        };
      case 9:
        return {
          kind: "noteOn",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          note: cv.noteNumber ?? 0,
          velocity: cv.velocity16 ?? 0,
          attributeType: cv.attributeType,
          attributeData: cv.attributeData16,
        };
      case 10:
        return {
          kind: "polyPressure",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          note: cv.noteNumber ?? 0,
          pressure: cv.polyPressure32 ?? 0,
        };
      case 11:
        return {
          kind: "controlChange",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          controller: cv.control ?? 0,
          value: cv.controlValue32 ?? 0,
        };
      case 12:
        return {
          kind: "programChange",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          program: cv.program ?? 0,
          bankMsb: cv.bankMsb,
          bankLsb: cv.bankLsb,
        };
      case 13:
        return {
          kind: "channelPressure",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          pressure: cv.channelPressure32 ?? 0,
        };
      case 14:
        return {
          kind: "pitchBend",
          group: (packet as UmpPacket64).group ?? 0,
          channel: channel ?? 0,
          value: cv.pitchBend32 ?? 0,
        };
      case 15: {
        if (cv.rpnIndexMsb !== undefined && cv.rpnIndexLsb !== undefined && cv.rpnData32 !== undefined) {
          return {
            kind: "rpn",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            bank: cv.rpnIndexMsb,
            index: cv.rpnIndexLsb,
            value: cv.rpnData32,
          };
        }
        if (cv.nrpnIndexMsb !== undefined && cv.nrpnIndexLsb !== undefined && cv.nrpnData32 !== undefined) {
          return {
            kind: "nrpn",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            bank: cv.nrpnIndexMsb,
            index: cv.nrpnIndexLsb,
            value: cv.nrpnData32,
          };
        }
        if (cv.rpnIndexMsb !== undefined && cv.rpnIndexLsb !== undefined && cv.rpnDelta32 !== undefined) {
          return {
            kind: "rpnRelative",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            bank: cv.rpnIndexMsb,
            index: cv.rpnIndexLsb,
            delta: cv.rpnDelta32,
          };
        }
        if (cv.nrpnIndexMsb !== undefined && cv.nrpnIndexLsb !== undefined && cv.nrpnDelta32 !== undefined) {
          return {
            kind: "nrpnRelative",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            bank: cv.nrpnIndexMsb,
            index: cv.nrpnIndexLsb,
            delta: cv.nrpnDelta32,
          };
        }
        if (cv.noteNumber !== undefined && (cv.detach !== undefined || cv.reset !== undefined)) {
          return {
            kind: "perNoteManagement",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            note: cv.noteNumber ?? 0,
            detach: Boolean(cv.detach),
            reset: Boolean(cv.reset),
          };
        }
        if (cv.regPerNoteCtrlIndex !== undefined && cv.regPerNoteCtrlValue32 !== undefined) {
          return {
            kind: "perNoteRegisteredController",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            note: cv.noteNumber ?? 0,
            controller: cv.regPerNoteCtrlIndex,
            value: cv.regPerNoteCtrlValue32,
          };
        }
        if (cv.assignPerNoteCtrlIndex !== undefined && cv.assignPerNoteCtrlValue32 !== undefined) {
          return {
            kind: "perNoteAssignableController",
            group: (packet as UmpPacket64).group ?? 0,
            channel: channel ?? 0,
            note: cv.noteNumber ?? 0,
            controller: cv.assignPerNoteCtrlIndex,
            value: cv.assignPerNoteCtrlValue32,
          };
        }
        return null;
      }
      default:
        return null;
    }
  }
  if (packet.messageType === 13) {
    const p = packet as UmpPacket128;
    const body: any = p.body;
    const channel = body.address?.scope === "channel" ? body.address.channel : undefined;
    switch (`${body.statusClass}-${body.status}`) {
      case "16-1":
        return { kind: "flexTempo", group: p.group ?? 0, channel, bpm: body.data?.bpm ?? 0 };
      case "16-2":
        return { kind: "flexTimeSignature", group: p.group ?? 0, channel, numerator: body.data?.numerator ?? 0, denominatorPow2: body.data?.denominatorPow2 ?? 0 };
      case "16-4":
        return { kind: "flexKeySignature", group: p.group ?? 0, channel, key: body.data?.key ?? "" };
      case "17-2":
        return { kind: "flexLyric", group: p.group ?? 0, channel, text: body.data?.lyric ?? "" };
      default:
        return null;
    }
  }
  if (packet.messageType === 5) {
    const p = packet as UmpPacket128;
    const body: any = p.body;
    if (body.kind === "sysex8" && body.sysex8) {
      const syx: SysEx8Event = {
        kind: "sysex8",
        group: p.group ?? 0,
        manufacturerId: body.sysex8.manufacturerId ?? [],
        payload: Uint8Array.from(body.sysex8.data ?? []),
      };
      const maybeCi = decodeMidiCiFromSysEx(syx);
      if (maybeCi) return midiCiToEvent(maybeCi);
      return syx;
    }
    return null;
  }
  if (packet.messageType === 1) {
    const sys = (packet as UmpPacket32).body as any;
    return {
      kind: "system",
      group: (packet as UmpPacket32).group ?? 0,
      status: sys.status,
      data1: sys.data1,
      data2: sys.data2,
    };
  }
  if (packet.messageType === 2) {
    const body = (packet as UmpPacket32).body as any;
    const status = ((body.statusNibble ?? 0) << 4) | (body.channel ?? 0);
    const event: Midi1ChannelVoiceEvent = {
      kind: "midi1ChannelVoice",
      group: (packet as UmpPacket32).group ?? 0,
      status,
    };
    if ("noteNumber" in body) event.data1 = body.noteNumber;
    if ("velocity7" in body) event.data2 = body.velocity7;
    if ("pressure7" in body && body.statusNibble === 10) event.data2 = body.pressure7;
    if ("control" in body) event.data1 = body.control;
    if ("value7" in body) event.data2 = body.value7;
    if ("program" in body) event.data1 = body.program;
    if ("pressure7" in body && body.statusNibble === 13) event.data1 = body.pressure7;
    if ("pitchBend14" in body) {
      const val = body.pitchBend14 ?? 0;
      event.data1 = val & 0x7f;
      event.data2 = (val >> 7) & 0x7f;
    }
    return event;
  }
  if (packet.messageType === 0) {
    const body = (packet as UmpPacket32).body as any;
    const opcode = body.opcode ?? 0;
    const status: UtilityEvent["status"] = opcode === 1 ? "jrClock" : opcode === 2 ? "jrTimestamp" : "noop";
    const value = opcode === 1 ? body.jrClock?.timestamp32 : opcode === 2 ? body.jrTimestamp?.time15 : undefined;
    return { kind: "utility", status, value };
  }
  return null;
}

export function schemaPacketToWords(packet: unknown): Uint32Array[] | null {
  const event = schemaPacketToEvent(packet);
  if (!event) return null;
  if (event.kind === "sysex7") {
    return fragmentSysEx7(event.manufacturerId, event.payload, event.group);
  }
  if (event.kind === "sysex8") {
    return fragmentSysEx8(event.manufacturerId, event.payload, event.group);
  }
  if (event.kind === "stream") {
    return [packStream(event)];
  }
  if (event.kind === "rawUMP") {
    return [event.words instanceof Uint32Array ? event.words : Uint32Array.from(event.words)];
  }
  return [encodeUmp(event)];
}

export function eventToSchemaPacketWords(event: Midi2Event): Uint32Array[] | null {
  const packet = eventToSchemaPacket(event);
  if (!packet) return null;
  return schemaPacketToWords(packet);
}

export function validateSchemaPacket(packet: unknown): packet is UmpPacket {
  return isUmpPacket(packet);
}

export function decodeWordsToSchemaPacket(words: ArrayLike<number>): UmpPacket | null {
  const event = decodeUmp(words);
  if (!event) return null;
  return eventToSchemaPacket(event);
}

function sysex7ToPackets(payload: number[]): { streamStatus: "single" | "start" | "continue" | "end"; payload: number[] }[] {
  if (payload.length <= 6) {
    return [{ streamStatus: "single", payload }];
  }
  const packets: { streamStatus: "single" | "start" | "continue" | "end"; payload: number[] }[] = [];
  let remaining = payload.slice();
  packets.push({ streamStatus: "start", payload: remaining.splice(0, 6) });
  while (remaining.length > 6) {
    packets.push({ streamStatus: "continue", payload: remaining.splice(0, 6) });
  }
  packets.push({ streamStatus: "end", payload: remaining });
  return packets;
}

function reassembleSysEx7FromPackets(
  manufacturerId: number[],
  packets: { streamStatus: "single" | "start" | "continue" | "end"; payload: number[] }[],
): { manufacturerId: number[]; payload: number[] } {
  const payload: number[] = [];
  for (const p of packets) {
    payload.push(...p.payload);
  }
  return { manufacturerId, payload };
}

function sysEx7BodyFromPayload(
  manufacturerId: number[],
  payload: Uint8Array,
): { manufacturerId: number[]; packets: { streamStatus: "single" | "start" | "continue" | "end"; payload: number[] }[] } {
  return {
    manufacturerId,
    packets: sysex7ToPackets(Array.from(payload)),
  };
}

function packGeneric32(packet: UmpPacket32): Uint32Array {
  const mt = packet.messageType ?? 0;
  if (mt === STREAM_MT) {
    return packStreamFromBody(packet);
  }
  const group = packet.group ?? 0;
  const opcode = (packet as any).body?.opcode ?? 0;
  const word0 = ((mt & 0xf) << 28) | ((group & 0xf) << 24) | ((opcode & 0xff) << 16);
  return new Uint32Array([word0 >>> 0]);
}

function opcodeNumber(opcode: StreamEvent["opcode"]): 0 | 1 | 2 | 3 {
  switch (opcode) {
    case "endpointDiscovery":
      return 0;
    case "streamConfigRequest":
    case "streamConfigNotification":
      return 1;
    case "functionBlockDiscovery":
    case "functionBlockInfo":
      return 2;
    case "processInquiry":
    case "processInquiryReply":
      return 3;
    default:
      return 0;
  }
}

function streamBodyToEvent(group: number, body: StreamBody): StreamEvent {
  const opcode = body.opcode;
  if (opcode === 0) {
    return {
      kind: "stream",
      group,
      opcode: "endpointDiscovery",
      endpointDiscovery: body.endpointDiscovery,
    };
  }
  if (opcode === 1) {
    return {
      kind: "stream",
      group,
      opcode: body.streamConfigRequest ? "streamConfigRequest" : "streamConfigNotification",
      streamConfigRequest: body.streamConfigRequest,
      streamConfigNotification: body.streamConfigNotification,
    };
  }
  if (opcode === 3) {
    if (body.processInquiryReply) {
      return {
        kind: "stream",
        group,
        opcode: "processInquiryReply",
        processInquiryReply: body.processInquiryReply,
      };
    }
    return {
      kind: "stream",
      group,
      opcode: "processInquiry",
      processInquiry: body.processInquiry,
    };
  }
  return {
    kind: "stream",
    group,
    opcode: body.functionBlockDiscovery ? "functionBlockDiscovery" : "functionBlockInfo",
    functionBlockDiscovery: body.functionBlockDiscovery,
    functionBlockInfo: body.functionBlockInfo,
  };
}

function streamBodyFromEvent(stream: StreamEvent): StreamBody {
  return {
    opcode: opcodeNumber(stream.opcode),
    endpointDiscovery: stream.endpointDiscovery,
    streamConfigRequest: stream.streamConfigRequest,
    streamConfigNotification: stream.streamConfigNotification,
    functionBlockDiscovery: stream.functionBlockDiscovery,
    functionBlockInfo: stream.functionBlockInfo,
    processInquiry: stream.processInquiry,
    processInquiryReply: stream.processInquiryReply,
  };
}

function profileToBody(evt: ProfileEvent): Uint8Array {
  const base: Record<string, any> = {
    command: evt.command,
  };
  if (evt.profileId) base.profileId = evt.profileId;
  if (evt.target) base.target = evt.target;
  if (evt.channels) base.channels = evt.channels;
  if (evt.details) base.details = evt.details;
  const bytes = new TextEncoder().encode(JSON.stringify(base));
  return Uint8Array.from(bytes);
}

function propertyExchangeToBody(evt: PropertyExchangeEvent): Uint8Array {
  const base: Record<string, any> = {
    command: evt.command,
    requestId: evt.requestId,
    encoding: evt.encoding,
    header: evt.header,
  };
  if (evt.data instanceof Uint8Array) {
    base.data = Array.from(evt.data);
  } else if (evt.data) {
    base.data = evt.data;
  }
  if (evt.ack) {
    base.ack = evt.ack.ack;
    base.statusCode = evt.ack.statusCode;
    base.message = evt.ack.message;
  }
  if (!evt.header && evt.data instanceof Uint8Array) {
    base.header = { length: evt.data.length };
  }
  const bytes = new TextEncoder().encode(JSON.stringify(base));
  return Uint8Array.from(bytes);
}

function midiCiToEvent(env: MidiCiEvent): Midi2Event {
  switch (env.subId2) {
    case 0x20:
      return sanitizeProfileEvent(
        {
          kind: "profile",
          group: env.group,
          ...decodeProfileBody(env.payload),
        },
        env.group,
      );
    case 0x21:
      return sanitizePeEvent(
        {
          kind: "propertyExchange",
          group: env.group,
          ...decodePropertyExchangeBody(env.payload),
        },
        env.group,
      );
    case 0x22:
      return {
        kind: "processInquiry",
        group: env.group,
        ...decodeProcessInquiryBody(env.payload),
      };
    default:
      return env;
  }
}

function decodeProfileBody(payload: Uint8Array): Omit<ProfileEvent, "kind" | "group"> {
  try {
    const text = new TextDecoder().decode(payload);
    const obj = JSON.parse(text);
    const valid = new Set([
      "inquiry",
      "reply",
      "addedReport",
      "removedReport",
      "setOn",
      "setOff",
      "enabledReport",
      "disabledReport",
      "detailsInquiry",
      "detailsReply",
      "profileSpecificData",
    ]);
    if (!obj.command || !valid.has(obj.command)) return { command: "reply", details: { payload: Array.from(payload) } };
    const evt: Omit<ProfileEvent, "kind" | "group"> = {
      command: obj.command,
      profileId: obj.profileId,
      target: obj.target,
      channels: obj.channels,
      details: obj.details,
    };
    return evt;
  } catch {
    return { command: "reply", details: { payload: Array.from(payload) } };
  }
}

function hexStringToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) {
    throw new Error("Hex string length must be even.");
  }
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < clean.length; i += 2) {
    out[i / 2] = parseInt(clean.slice(i, i + 2), 16);
  }
  return out;
}

function decodePropertyExchangeBody(payload: Uint8Array): Omit<PropertyExchangeEvent, "kind" | "group"> {
  try {
    const text = new TextDecoder().decode(payload);
    const obj = JSON.parse(text);
    const valid = new Set([
      "capInquiry",
      "capReply",
      "get",
      "getReply",
      "set",
      "setReply",
      "subscribe",
      "subscribeReply",
      "notify",
      "terminate",
    ]);
    if (!obj.command || !valid.has(obj.command)) return { command: "notify", data: payload };
    const parsedData =
      obj.encoding && typeof obj.data === "string" && obj.data.startsWith("0x")
        ? hexStringToBytes(obj.data)
        : obj.data;
    const evt: Omit<PropertyExchangeEvent, "kind" | "group"> = {
      command: obj.command,
      requestId: obj.requestId,
      encoding: obj.encoding,
      header: obj.header,
      data: parsedData,
      ack: obj.ack !== undefined ? { ack: !!obj.ack, statusCode: obj.statusCode, message: obj.message } : undefined,
    };
    return evt;
  } catch {
    return { command: "notify", data: payload };
  }
}

export function reassemblePeChunks(chunks: PropertyExchangeEvent[]): PropertyExchangeEvent | null {
  if (!chunks.length) return null;
  const binaryChunks = chunks.every(c => c.data instanceof Uint8Array);
  if (!binaryChunks) return null;
  const sorted = chunks
    .slice()
    .sort((a, b) => Number((a.header?.offset as number) ?? 0) - Number((b.header?.offset as number) ?? 0));
  const buffers: number[] = [];
  let expectedOffset = 0;
  for (const chunk of sorted) {
    const offset = Number((chunk.header as any)?.offset ?? 0);
    const length = (chunk.data as Uint8Array).length;
    if (offset !== expectedOffset) {
      return null;
    }
    buffers.push(...Array.from(chunk.data as Uint8Array));
    expectedOffset += length;
  }
  const base = sorted[0];
  const data = Uint8Array.from(buffers);
  const header = { ...(base.header ?? {}), length: data.length };
  return { ...base, data, header, command: base.command, requestId: base.requestId };
}

function sanitizeProfileEvent(evt: ProfileEvent, group: number): ProfileEvent {
  const requiresProfileId = new Set(["setOn", "setOff", "addedReport", "removedReport", "enabledReport", "disabledReport", "detailsInquiry", "detailsReply", "profileSpecificData"]);
  if (requiresProfileId.has(evt.command) && !evt.profileId) {
    return { command: "reply", kind: "profile", group, details: { payload: [] } };
  }
  if ((evt.command === "setOn" || evt.command === "setOff" || evt.command === "detailsInquiry") && !evt.target) {
    return { command: "reply", kind: "profile", group, details: { payload: [] } };
  }
  if (evt.target === "channel" && (!Array.isArray(evt.channels) || evt.channels.length === 0)) {
    return { command: "reply", kind: "profile", group, details: { payload: [] } };
  }
  if (evt.target && !["channel", "group", "functionBlock"].includes(evt.target)) {
    return { command: "reply", kind: "profile", group, details: { payload: [] } };
  }
  if (evt.details && typeof evt.details !== "object") {
    return { command: "reply", kind: "profile", group, details: { payload: [] } };
  }
  return { ...evt, group, kind: "profile" };
}

function sanitizePeEvent(evt: PropertyExchangeEvent, group: number): PropertyExchangeEvent {
  const needsRequestId = new Set(["get", "getReply", "set", "setReply", "subscribe", "subscribeReply", "notify", "terminate"]);
  if (needsRequestId.has(evt.command) && evt.requestId === undefined) {
    return { kind: "propertyExchange", group, command: "notify", data: evt.data, header: evt.header };
  }
  if (evt.encoding && !["json", "binary", "json+zlib", "binary+zlib", "mcoded7"].includes(evt.encoding)) {
    return { kind: "propertyExchange", group, command: "notify", data: evt.data, header: evt.header };
  }
  if (evt.header && typeof evt.header !== "object") {
    return { kind: "propertyExchange", group, command: "notify", data: evt.data };
  }
  if (evt.data && !(evt.data instanceof Uint8Array) && typeof evt.data !== "object") {
    return { kind: "propertyExchange", group, command: "notify", data: undefined };
  }
  if (evt.header && typeof (evt.header as any).offset !== "undefined" && typeof (evt.header as any).length !== "undefined") {
    const offset = Number((evt.header as any).offset);
    const length = Number((evt.header as any).length);
    if (!Number.isFinite(offset) || !Number.isFinite(length) || offset < 0 || length < 0) {
      return { kind: "propertyExchange", group, command: "notify", data: undefined };
    }
  }
  return { ...evt, group, kind: "propertyExchange" };
}

function processInquiryToBody(evt: ProcessInquiryEvent): Uint8Array {
  const base: Record<string, any> = {
    command: evt.command,
    filters: evt.filters,
  };
  const bytes = new TextEncoder().encode(JSON.stringify(base));
  return Uint8Array.from(bytes);
}

function decodeProcessInquiryBody(payload: Uint8Array): Omit<ProcessInquiryEvent, "kind" | "group"> {
  try {
    const obj = JSON.parse(new TextDecoder().decode(payload));
    const valid = new Set(["capInquiry", "capReply", "messageReport", "messageReportReply", "endReport"]);
    if (!obj.command || !valid.has(obj.command)) {
      return { command: "endReport" };
    }
    return {
      command: obj.command,
      filters: typeof obj.filters === "object" ? obj.filters : undefined,
    };
  } catch {
    return { command: "endReport" };
  }
}

function packStream(stream: StreamEvent): Uint32Array {
  const mt = STREAM_MT << 28;
  const group = (stream.group & 0xf) << 24;
  const opcodeByte = opcodeNumber(stream.opcode);
  if (stream.opcode === "streamConfigRequest" || stream.opcode === "streamConfigNotification") {
    const flags = encodeStreamFlags(stream.streamConfigRequest ?? stream.streamConfigNotification ?? {}, stream.opcode === "streamConfigNotification");
    const word0 = mt | group | (STREAM_OPCODE_CONFIG << 16) | (flags << 8);
    return new Uint32Array([word0 >>> 0]);
  }
  if (stream.opcode === "functionBlockInfo" && stream.functionBlockInfo) {
    const idx = stream.functionBlockInfo.index ?? 0;
    const firstGroup = stream.functionBlockInfo.firstGroup ?? 0;
    const groupCount = stream.functionBlockInfo.groupCount ?? 0;
    const byte2 = idx & 0xff;
    const byte3 = ((firstGroup & 0x0f) << 4) | (groupCount & 0x0f);
    const word0 = mt | group | (opcodeByte << 16) | (byte2 << 8) | byte3;
    return new Uint32Array([word0 >>> 0]);
  }
  if (stream.opcode === "functionBlockDiscovery" && stream.functionBlockDiscovery) {
    const filter = stream.functionBlockDiscovery.filterBitmap ?? 0;
    const byte2 = (filter >> 8) & 0xff;
    const byte3 = filter & 0xff;
    const word0 = mt | group | (STREAM_OPCODE_FUNCTION_BLOCK << 16) | (byte2 << 8) | byte3;
    return new Uint32Array([word0 >>> 0]);
  }
  if (stream.opcode === "processInquiry" && stream.processInquiry) {
    const fb = stream.processInquiry.functionBlock ?? 0;
    const part = stream.processInquiry.part ?? 0;
    const word0 = mt | group | (STREAM_OPCODE_PROCESS_INQUIRY << 16) | ((fb & 0x7f) << 8) | (part & 0x0f);
    return new Uint32Array([word0 >>> 0]);
  }
  if (stream.opcode === "processInquiryReply" && stream.processInquiryReply) {
    const fb = stream.processInquiryReply.functionBlock ?? 0;
    const part = stream.processInquiryReply.part ?? 0;
    const word0 = mt | group | (STREAM_OPCODE_PROCESS_INQUIRY << 16) | ((fb & 0x7f) << 8) | ((part & 0x0f) | 0x80);
    return new Uint32Array([word0 >>> 0]);
  }
  const word0 = mt | group | (opcodeByte << 16);
  return new Uint32Array([word0 >>> 0]);
}

function packStreamFromBody(packet: UmpPacket32): Uint32Array {
  const body = packet.body as any;
  const group = packet.group ?? 0;
  const opcodeByte = body?.opcode ?? 0;
  let byte2 = 0;
  let byte3 = 0;
  if (body?.streamConfigRequest) {
    byte2 = encodeStreamFlags(body.streamConfigRequest, false);
  } else if (body?.streamConfigNotification) {
    byte2 = encodeStreamFlags(body.streamConfigNotification, true);
  } else if (body?.functionBlockDiscovery) {
    const filter = body.functionBlockDiscovery.filterBitmap ?? 0;
    byte2 = (filter >> 8) & 0xff;
    byte3 = filter & 0xff;
  } else if (body?.functionBlockInfo) {
    byte2 = body.functionBlockInfo.index ?? 0;
    byte3 = ((body.functionBlockInfo.firstGroup ?? 0) << 4) | (body.functionBlockInfo.groupCount ?? 0);
  } else if (body?.processInquiry) {
    byte2 = (body.processInquiry.functionBlock ?? 0) & 0x7f;
    byte3 = (body.processInquiry.part ?? 0) & 0x0f;
  } else if (body?.processInquiryReply) {
    byte2 = (body.processInquiryReply.functionBlock ?? 0) & 0x7f;
    byte3 = ((body.processInquiryReply.part ?? 0) & 0x0f) | 0x80;
  }
  const word0 = (STREAM_MT << 28) | ((group & 0x0f) << 24) | ((opcodeByte & 0xff) << 16) | ((byte2 & 0xff) << 8) | (byte3 & 0xff);
  return new Uint32Array([word0 >>> 0]);
}

function encodeStreamFlags(cfg: any, isNotification: boolean): number {
  let flags = 0x20;
  if ((cfg.protocol ?? "midi1") === "midi2") flags |= 0x01;
  if (cfg.jrTimestampsTx) flags |= 0x02;
  if (cfg.jrTimestampsRx && !isNotification) flags |= 0x04;
  flags &= 0x27; // clear reserved bits (7:5,3)
  return flags;
}

export function decodeStreamWord(word: number): StreamEvent | null {
  const mt = (word >>> 28) & 0xf;
  if (mt !== STREAM_MT) return null;
  // Reserved bit 3 must be zero
  if ((word & 0x00000008) !== 0) return null;
  const group = (word >>> 24) & 0xf;
  const opcodeByte = (word >>> 16) & 0xff;
  const byte2 = (word >>> 8) & 0xff;
  const byte3 = word & 0xff;
  if (opcodeByte === STREAM_OPCODE_ENDPOINT && (byte2 !== 0 || byte3 !== 0)) {
    return null; // reserved bits set for endpoint discovery
  }
  if (opcodeByte === 0x01) {
    const protocol = (byte2 & 0x01) !== 0 ? "midi2" : "midi1";
    const jrTx = (byte2 & 0x02) !== 0;
    const jrRx = (byte2 & 0x04) !== 0;
    const isNotification = !jrRx;
    const evt: StreamEvent = {
      kind: "stream",
      group,
      opcode: isNotification ? "streamConfigNotification" : "streamConfigRequest",
      streamConfigRequest: isNotification ? undefined : { protocol, jrTimestampsTx: jrTx, jrTimestampsRx: jrRx },
      streamConfigNotification: isNotification ? { protocol, jrTimestampsTx: jrTx, jrTimestampsRx: jrRx } : undefined,
    };
    return evt;
  }
  if (opcodeByte === 0x02) {
    if (byte2 >= 0x80) {
      const filterBitmap = (byte2 << 8) | byte3;
      return {
        kind: "stream",
        group,
        opcode: "functionBlockDiscovery",
        functionBlockDiscovery: { filterBitmap },
      };
    }
    const index = byte2;
    const firstGroup = (byte3 >> 4) & 0x0f;
    const groupCount = byte3 & 0x0f;
    return {
      kind: "stream",
      group,
      opcode: "functionBlockInfo",
      functionBlockInfo: { index, firstGroup, groupCount },
    };
  }
  if (opcodeByte === STREAM_OPCODE_PROCESS_INQUIRY) {
    const fb = byte2 & 0x7f;
    const part = byte3 & 0x0f;
    const isReply = (byte3 & 0x80) !== 0;
    if (isReply) {
      return {
        kind: "stream",
        group,
        opcode: "processInquiryReply",
        processInquiryReply: { functionBlock: fb, part },
      };
    }
    return {
      kind: "stream",
      group,
      opcode: "processInquiry",
      processInquiry: { functionBlock: fb, part },
    };
  }
  return {
    kind: "stream",
    group,
    opcode: "endpointDiscovery",
  };
}
