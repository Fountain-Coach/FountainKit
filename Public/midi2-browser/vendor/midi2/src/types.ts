export type MidiTimestamp = number;

export interface Midi2ChannelVoiceBase {
  group: number;
  channel: number;
  timestamp?: MidiTimestamp;
}

export interface Midi2NoteOnEvent extends Midi2ChannelVoiceBase {
  kind: "noteOn";
  note: number;
  velocity: number;
  attributeType?: number;
  attributeData?: number;
}

export interface Midi2NoteOffEvent extends Midi2ChannelVoiceBase {
  kind: "noteOff";
  note: number;
  velocity?: number;
  attributeType?: number;
  attributeData?: number;
}

export interface Midi2PolyPressureEvent extends Midi2ChannelVoiceBase {
  kind: "polyPressure";
  note: number;
  pressure: number;
}

export interface Midi2ControlChangeEvent extends Midi2ChannelVoiceBase {
  kind: "controlChange";
  controller: number;
  value: number;
}

export interface Midi2ProgramChangeEvent extends Midi2ChannelVoiceBase {
  kind: "programChange";
  program: number;
  bankMsb?: number;
  bankLsb?: number;
}

export interface Midi2ChannelPressureEvent extends Midi2ChannelVoiceBase {
  kind: "channelPressure";
  pressure: number;
}

export interface Midi2PitchBendEvent extends Midi2ChannelVoiceBase {
  kind: "pitchBend";
  value: number;
}

export interface Midi2RpnEvent extends Midi2ChannelVoiceBase {
  kind: "rpn";
  bank: number;
  index: number;
  value: number;
}

export interface Midi2NrpnEvent extends Midi2ChannelVoiceBase {
  kind: "nrpn";
  bank: number;
  index: number;
  value: number;
}

export interface Midi2RpnRelativeEvent extends Midi2ChannelVoiceBase {
  kind: "rpnRelative";
  bank: number;
  index: number;
  delta: number;
}

export interface Midi2NrpnRelativeEvent extends Midi2ChannelVoiceBase {
  kind: "nrpnRelative";
  bank: number;
  index: number;
  delta: number;
}

export interface Midi2PerNoteManagementEvent extends Midi2ChannelVoiceBase {
  kind: "perNoteManagement";
  note: number;
  detach: boolean;
  reset: boolean;
}

export interface Midi2PerNoteRegisteredControllerEvent extends Midi2ChannelVoiceBase {
  kind: "perNoteRegisteredController";
  note: number;
  controller: number;
  value: number;
}

export interface Midi2PerNoteAssignableControllerEvent extends Midi2ChannelVoiceBase {
  kind: "perNoteAssignableController";
  note: number;
  controller: number;
  value: number;
}

export interface Midi2PerNotePitchBendEvent extends Midi2ChannelVoiceBase {
  kind: "perNotePitchBend";
  note: number;
  value: number;
}

export interface SysEx7Event {
  kind: "sysex7";
  group: number;
  manufacturerId: number[];
  payload: Uint8Array;
  timestamp?: MidiTimestamp;
}

export interface SysEx8Event {
  kind: "sysex8";
  group: number;
  manufacturerId: number[];
  payload: Uint8Array;
  timestamp?: MidiTimestamp;
}

export interface MidiCiEvent {
  kind: "midiCi";
  group: number;
  scope: "nonRealtime" | "realtime";
  subId2: number;
  version: number;
  payload: Uint8Array;
  format: "sysex7" | "sysex8";
  timestamp?: MidiTimestamp;
}

export interface Midi2SystemEvent {
  kind: "system";
  group: number;
  status: 0xf1 | 0xf2 | 0xf3 | 0xf6 | 0xf8 | 0xfa | 0xfb | 0xfc | 0xfe | 0xff;
  data1?: number;
  data2?: number;
  timestamp?: MidiTimestamp;
}

export interface Midi1ChannelVoiceEvent {
  kind: "midi1ChannelVoice";
  group: number;
  status: number;
  data1?: number;
  data2?: number;
  timestamp?: MidiTimestamp;
}

export interface UtilityEvent {
  kind: "utility";
  status: "noop" | "jrClock" | "jrTimestamp";
  value?: number;
  group?: number;
  timestampGroup?: number;
  timestamp?: MidiTimestamp;
}

export interface FlexTempoEvent {
  kind: "flexTempo";
  group: number;
  channel?: number;
  bpm: number;
  timestamp?: MidiTimestamp;
}

export interface FlexTimeSignatureEvent {
  kind: "flexTimeSignature";
  group: number;
  channel?: number;
  numerator: number;
  denominatorPow2: number;
  timestamp?: MidiTimestamp;
}

export interface FlexKeySignatureEvent {
  kind: "flexKeySignature";
  group: number;
  channel?: number;
  key: string;
  timestamp?: MidiTimestamp;
}

export interface FlexLyricEvent {
  kind: "flexLyric";
  group: number;
  channel?: number;
  text: string;
  timestamp?: MidiTimestamp;
}

export interface ProfileEvent {
  kind: "profile";
  group: number;
  command:
    | "inquiry"
    | "reply"
    | "addedReport"
    | "removedReport"
    | "setOn"
    | "setOff"
    | "enabledReport"
    | "disabledReport"
    | "detailsInquiry"
    | "detailsReply"
    | "profileSpecificData";
  profileId?: string;
  target?: "channel" | "group" | "functionBlock";
  channels?: number[];
  details?: Record<string, unknown>;
  timestamp?: MidiTimestamp;
}

export interface PropertyExchangeEvent {
  kind: "propertyExchange";
  group: number;
  command: "capInquiry" | "capReply" | "get" | "getReply" | "set" | "setReply" | "subscribe" | "subscribeReply" | "notify" | "terminate";
  requestId?: number;
  encoding?: "json" | "binary" | "json+zlib" | "binary+zlib" | "mcoded7";
  header?: Record<string, unknown>;
  data?: Record<string, unknown> | Uint8Array;
  ack?: { ack: boolean; statusCode?: number; message?: string };
  timestamp?: MidiTimestamp;
}

export interface ProcessInquiryEvent {
  kind: "processInquiry";
  group: number;
  command: "capInquiry" | "capReply" | "messageReport" | "messageReportReply" | "endReport";
  filters?: Record<string, number>;
  timestamp?: MidiTimestamp;
}

export interface RawUMPEvent {
  kind: "rawUMP";
  words: Uint32Array;
  timestamp?: MidiTimestamp;
}

export type StreamOpcode =
  | "endpointDiscovery"
  | "streamConfigRequest"
  | "streamConfigNotification"
  | "functionBlockDiscovery"
  | "functionBlockInfo"
  | "processInquiry"
  | "processInquiryReply";

export interface StreamEvent {
  kind: "stream";
  group: number;
  opcode: StreamOpcode;
  endpointDiscovery?: { majorVersion?: number; minorVersion?: number; maxGroups?: number };
  streamConfigRequest?: { protocol?: "midi1" | "midi2"; jrTimestampsTx?: boolean; jrTimestampsRx?: boolean };
  streamConfigNotification?: { protocol?: "midi1" | "midi2"; jrTimestampsTx?: boolean; jrTimestampsRx?: boolean };
  functionBlockDiscovery?: { filterBitmap?: number };
  functionBlockInfo?: { index?: number; firstGroup?: number; groupCount?: number };
  processInquiry?: { functionBlock?: number; part?: number };
  processInquiryReply?: { functionBlock?: number; part?: number };
  timestamp?: MidiTimestamp;
}

export type Midi2Event =
  | Midi2NoteOnEvent
  | Midi2NoteOffEvent
  | Midi2PolyPressureEvent
  | Midi2ControlChangeEvent
  | Midi2ProgramChangeEvent
  | Midi2ChannelPressureEvent
  | Midi2PitchBendEvent
  | Midi2RpnEvent
  | Midi2NrpnEvent
  | Midi2RpnRelativeEvent
  | Midi2NrpnRelativeEvent
  | Midi2PerNoteManagementEvent
  | Midi2PerNoteRegisteredControllerEvent
  | Midi2PerNoteAssignableControllerEvent
  | Midi2PerNotePitchBendEvent
  | Midi2SystemEvent
  | Midi1ChannelVoiceEvent
  | UtilityEvent
  | FlexTempoEvent
  | FlexTimeSignatureEvent
  | FlexKeySignatureEvent
  | FlexLyricEvent
  | SysEx7Event
  | SysEx8Event
  | MidiCiEvent
  | StreamEvent
  | ProfileEvent
  | PropertyExchangeEvent
  | ProcessInquiryEvent
  | RawUMPEvent;

export type MidiEventHandler = (event: Midi2Event) => void;
