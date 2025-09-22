# FountainGatewayKit Quick Reference

This package implements the Fountain Gateway's policy orchestration stack. It
pulls together authentication, curation, policy enforcement, and LLM-backed
personas to vet incoming traffic before routing allowed requests to downstream
services. Use this document as a quick refresher on how the gateway, plugins,
and personas collaborate.

## Gateway, plugins, and personas — Explained

> **Q:** I still struggle to understand how the gateway and personas actually
> work—the plugins, the chain reaction. Is it a call and response of an LLM
> talking in different personas to itself—requests to OpenAI—back and forth—or
> any other reasoning flow? Please explain.
>
> **A:** The Gateway server is the control-plane entry point for FountainKit:
> it authenticates inbound traffic, enforces policy, orchestrates persona
> checks, and then routes allowed requests to downstream services. It does this
> by composing a set of gateway plugins (auth, curation, LLM, policy
> enforcement, etc.) into a single executable.
>
> Persona logic is encapsulated in `GatewayPersona` implementations. Each
> persona exposes an `evaluate` function that returns `allow`, `deny`, or
> `escalate` based on the request it inspects.
>
> The `GatewayPersonaOrchestrator` calls the personas one after another. It
> short-circuits on a denial, remembers the first escalation, and only returns
> `allow` if every persona is comfortable. That’s the “chain reaction”: a
> deterministic decision tree, not free-form conversation between personas.
>
> The orchestrator itself even has a baseline system persona prompt (“You are
> the Gateway Persona Orchestrator…”) that tells the supervising LLM how to
> combine the sub-persona verdicts when an LLM is asked to perform
> orchestration externally.
>
> FountainKit maintains persona definitions in Markdown under
> `openapi/personas/`. The OpenAPI README explicitly lists which personas drive
> each gateway plugin; those Markdown files are the instructions injected when
> the LLM is asked to perform a plugin-specific task.
>
> Gateway plugins such as the Auth plugin load the appropriate persona text
> from disk and forward it—together with the runtime prompt—to an LLM Gateway
> endpoint via a minimal HTTP client (`LLMPluginClient`).
>
> For example, `authValidate` encodes the request body as JSON, sends it to the
> LLM with the Auth persona instructions, and treats the JSON the LLM returns
> as the validation result. Other plugins follow the same pattern, differing
> only in persona files and prompt content.
>
> When a request arrives, the Gateway server runs the configured plugins. Some
> plugins are purely deterministic, while LLM-backed ones ship a persona script
> plus the current context to the LLM Gateway. The LLM produces a response (for
> example, “deny because token scope is missing”), which the plugin turns into a
> `GatewayPersonaVerdict`.
>
> The orchestrator aggregates these verdicts. There’s no back-and-forth
> dialogue between personas; each persona runs independently, and the
> orchestrator synthesizes the final answer according to its static rules. The
> “chain reaction” terminology refers to this evaluation pipeline—plugins
> trigger persona checks, and the orchestrator reacts to their results—not to
> personas chatting with one another.
>
> In short, gateway personas are structured policy modules whose prompts live
> alongside the API specs. Plugins pass those prompts to an LLM to obtain
> decisions, and the orchestrator applies deterministic merge rules. It’s
> orchestration of specialized checks, not an internal conversation among
> personas.

