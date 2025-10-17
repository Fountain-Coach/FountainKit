LLM Doctor

Purpose: Provide a quick, non-UI assurance that a local LLM endpoint is available on this machine.

What it checks:
- OpenAI-compatible endpoints: http://127.0.0.1:11434 and http://127.0.0.1:8000 (/v1/models)
- Ollama classic API: http://127.0.0.1:11434/api/tags
- LocalAgent bridge: http://127.0.0.1:8080/health

Usage:
- swift run --package-path Packages/FountainApps llm-doctor
- swift run --package-path Packages/FountainApps llm-doctor --json
- ENGRAVER_LOCAL_LLM_URL=http://127.0.0.1:11434/v1/chat/completions swift run --package-path Packages/FountainApps llm-doctor

Exit codes:
- 0: A local LLM endpoint was detected (prints provider and URL)
- 1: No endpoint was found (prints attempted checks)

Environment variables:
- ENGRAVER_LOCAL_LLM_URL: Optional OpenAI-compatible endpoint to prefer.
- LLM_DOCTOR_TIMEOUT: Optional request timeout in seconds (default ~2.5s).
- LLM_DOCTOR_JSON=1: Force JSON output.

