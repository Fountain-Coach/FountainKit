# The Book of FountainAI — Plain Language

This is a story about what FountainAI is and why it exists, written to be readable without any special technical background. There will be some technical words, but each one is introduced gently and used consistently.

---

## 1. What FountainAI Is (In One Picture)

Imagine a studio where:

- Musicians play instruments.
- A mixing desk connects everything together.
- A notebook on the side table remembers every idea, setting, and experiment.

FountainAI is that whole studio, but for *interactive AI and music tools*:

- The **instruments** are the apps and surfaces you see and touch (sliders, pads, canvases, chat windows).
- The **mixing desk** is the runtime that connects instruments to services and models.
- The **notebook** is a shared memory called **FountainStore**, where prompts, facts, and settings live.

The goal: once something is described clearly in this studio (what an instrument can do, how it should behave), both humans and AI agents can operate it safely and repeatably.

---

## 2. Why FountainAI Exists

Modern AI tools often feel like one‑off demos: impressive once, hard to repeat, and easy to break as soon as you make changes. FountainAI takes the opposite approach.

We want:

- **Repeatable instruments** — if you discover a useful tool or UI, you can bring it back exactly as it was.
- **Explainable surfaces** — every instrument can describe itself in text and in structured form (what knobs it has, what each setting means).
- **Shared language** between humans, apps, and AI agents about what is possible and what is safe.

FountainAI offers a *studio where instruments can be designed, tested, and played* with the same care you would give a real musical instrument.

---

## 3. Three Planes (Without the Jargon)

Under the hood, the system has three “planes”. You do not need the technical names, but it helps to know what each plane is responsible for.

### 3.1 The Live Plane — “What’s happening right now”

This is where instruments are actually played:

- A canvas is zooming and panning.
- A MIDI controller is sending notes and control messages.
- An AI agent is changing values (like zoom or opacity) in real time.

Technically, this is powered by MIDI 2.0 and something called **Property Exchange**. You can think of Property Exchange as “a structured list of knobs and buttons that can be changed live”.

### 3.2 The Control Plane — “What tools exist and how to call them”

This plane answers questions like:

- “What services are available?”  
- “What does this endpoint or tool do?”  
- “If an AI wants to call a tool, how does it format the request?”

Here we use **OpenAPI**, which is simply a *formal description of an API* (what it can do, what it expects, and what it returns). FountainAI uses these descriptions to:

- Generate server code.
- Generate clients.
- Register tools that an AI can call safely.

You do not need to write OpenAPI yourself to benefit from it; you just need to know that “if it’s in the spec, everyone can see it, reuse it, and test it”.

### 3.3 The Memory Plane — “What we know and remember”

This is where **FountainStore** comes in. It is the shared notebook of the studio.

FountainStore remembers:

- **Prompts** that describe an instrument or app in human language (we call these **Teatro prompts**).
- **Facts** about instruments and agents: which properties exist, what they mean, and how they map to tools.
- **Indexes** of instruments and tools, so we can list them, lint them (check them), and keep them in sync.

The rule of the studio is simple:  
*If something is important for behaviour, it lives in FountainStore, not in ad‑hoc text files.*

---

## 4. Key Ideas and Words (Glossary)

This section defines words that show up often in the FountainAI ecosystem. You can scan it now or come back whenever a term feels slippery.

### Instrument

An **instrument** is any interactive surface that can be “played”:

- It might be a music interface, a canvas, a chat window, or a dashboard.
- It has controls (knobs, sliders, pads, properties) that can be set or read.
- It is driven by real‑time updates from people, AI agents, or both.

The test for “is this an instrument?” is:  
> Can we describe its controls and behaviour well enough that a robot (or AI agent) could operate it reliably?

### Agent

An **agent** is a logical actor with capabilities. In practice:

- Each agent has an **OpenAPI spec** describing what it can do.
- Agents can have **facts** in FountainStore that describe their capabilities in a more instrument‑friendly way.

Examples:

- A “planner” agent that turns goals into step‑by‑step plans.
- A “tools factory” agent that turns specs into callable tools.
- A “composer” agent that manipulates scores or scripts.

We often refer to agents using an ID like:  
`fountain.coach/agent/llm-chat/service`  
You can read that as: “the llm‑chat service agent in the Fountain Coach universe”.

### Teatro Prompt

A **Teatro prompt** is a carefully written description of an app or instrument:

- It explains the scene: what you see on screen, what the main controls are.
- It lists important properties and invariants (rules that should always hold).
- It serves as the *single source of truth* for how the surface should behave.

On boot, instruments:

- Fetch their Teatro prompt from FountainStore.
- Print it to logs so both humans and agents can see “what kind of surface this is”.

### Facts

**Facts** are structured JSON documents that describe capabilities. For example:

- What PE properties an instrument exposes (e.g. `canvas.zoom`, `canvas.translation.x`).
- How OpenAPI operations map to those properties.
- Invariants and metadata used by tests and hosts.

Facts are derived from OpenAPI specs (using the `openapi-to-facts` tool) and stored in FountainStore. You can think of them as the “machine‑friendly explanation of what the instrument or agent can do”.

### FountainStore

**FountainStore** is the shared memory. It stores:

- Pages (`prompt:<app-id>`) with segments:
  - `teatro.prompt` → full human‑readable prompt.
  - `facts` → structured JSON facts.
- Agent‑level documents (e.g. `facts:agent:<agentId>`, `secret:agent:<agentId>`).

Every serious surface or agent in the system has an entry here. This is how the studio stays coherent across restarts and machines.

### Tools and Tools Factory

A **tool** is a single callable operation exposed to an AI agent:

- It is defined by an OpenAPI operation (method + path + schema).
- It has a clear name, input shape, and output shape.

The **Tools Factory** is a service that:

- Reads OpenAPI specs.
- Registers operations as tools.
- Stores tool metadata in FountainStore so AI agents can discover and call them.

When you see scripts like `register-…-as-tools.sh`, they are usually:

1. Converting a spec to JSON.
2. Sending it to Tools Factory.
3. Making the operations available as tools.

### Instrument Index and Instrument Lint

The **instrument index** is a JSON file that lists all known instruments in the workspace:

- Where their tests live.
- Which spec and agent ID they are tied to.
- Which test symbols must exist (for example, `LLMChatAppTests`).

**Instrument lint** is a checker that reads this index and verifies:

- The spec exists.
- Facts exist in FountainStore.
- Tests and required symbols are present.

This is how the studio enforces that instruments are not just demos—they are maintained, testable products.

---

## 5. How a New Instrument Is Born (Story View)

Here is a simplified story of how a new instrument appears in FountainAI.

1. **You decide what you want.**  
   You give the system three pieces of information:
   - A short ID (for example `llm-chat`).
   - An agent ID (for example `fountain.coach/agent/llm-chat/service`).
   - A spec name (for example `llm-chat.yml`).

2. **The “instrument-new” tool scaffolds everything.**  
   This tool:
   - Creates a starter **OpenAPI spec** for your instrument, with routes like “get state” and “set state”.
   - Adds a row to the **facts mapping**, linking your spec to the agent ID.
   - Adds an entry to the **instrument index**, so linting and test discovery know about it.
   - Creates a **seeder** that writes the Teatro prompt and facts into FountainStore.
   - Creates a **test module** (and optional visual baselines) so behaviour can be verified.
   - Optionally creates an **app surface** using a GUI framework, so you can see and play the instrument.

3. **Facts are generated from the spec.**  
   The OpenAPI spec is turned into facts (a list of properties and mappings) and stored in FountainStore. At this point:
   - The instrument has a documented surface.
   - The MIDI host and other tools can load those facts.

4. **Linting keeps it honest.**  
   Instrument lint checks the whole setup:
   - Is the spec in place?
   - Do facts exist?
   - Do the declared tests and symbols exist?

If everything passes, your instrument is no longer a private experiment—it is a first‑class citizen in the FountainAI studio.

---

## 6. How to Read the Technical Book After This

There is a more detailed, engineer‑oriented document at:

- `docs/Book-of-FountainAI.md`

Once you are comfortable with the ideas in *this* plain‑language book, you can:

- Use this file as a map of concepts and vocabulary.
- Use the technical book to see where each idea lives in the codebase and services.

If you ever hit a term in the technical book that feels undefined, come back here first. If it is missing here too, that is a signal we should extend the glossary rather than forcing readers to guess.
