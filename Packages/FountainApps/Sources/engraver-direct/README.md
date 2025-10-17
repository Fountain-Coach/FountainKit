Engraver Direct

Minimal, no-gateway CLI that:
- Chats with a local LLM endpoint (OpenAI-compatible), defaulting to LocalAgent at http://127.0.0.1:8080/chat or Ollama at http://127.0.0.1:11434/v1/chat/completions.
- Talks to the Planner service to generate and (optionally) execute plans.

Usage
- Chat: swift run --package-path Packages/FountainApps engraver-direct chat "your prompt"
- Plan: swift run --package-path Packages/FountainApps engraver-direct plan "your objective"

Env
- LLM_URL: Override local LLM chat endpoint (default: http://127.0.0.1:8080/chat)
- PLANNER_URL: Planner base URL (default: http://127.0.0.1:8003)

