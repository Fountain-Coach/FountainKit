
# **Prometheus → LLM Telemetry Exchange Specification (FountainAI Architecture)**

## 1. System Architecture

This document defines the telemetry exchange pipeline between **Prometheus** and the **LLM reasoning layer** within FountainAI.  
It ensures the LLM can reason about live system telemetry safely and deterministically.

### Components
| Component | Role |
|------------|------|
| **Prometheus** | Collects raw time-series metrics from FountainAI microservices. |
| **Feature Extractor** | Summarizes, aggregates, and detects anomalies across metric streams. |
| **LLM Orchestrator** | Consumes summaries and applies structured reasoning templates. |
| **Policy Gate** | Validates and approves any proposed actions. |

Data flow:
```
Prometheus → Feature Extractor → LLM Orchestrator → Policy Gate → Human/Automation
```

---

## 2. Signal Summary Schema

Each metric signal is summarized as JSON:

```json
{
  "signal": "api_availability",
  "source": "prometheus",
  "query_id": "availability_by_service",
  "window": {"short": "5m", "mid": "1h", "long": "24h"},
  "stats": {
    "current": 0.9923,
    "mean": 0.9987,
    "p95": 0.9951
  },
  "anomalies": [{"t": "2025-10-28T08:12:00Z", "score": 3.1}],
  "correlates_with": ["error_rate_api", "latency_p99_payment"],
  "recent_changes": ["deploy:plan-service@1.4.7", "config:redis_ttl=60→10"],
  "slo": {"target": 0.999, "period": "30d", "budget_used_pct": 34.2}
}
```

---

## 3. API Endpoints

### **/signals**
- **Method:** POST  
- **Purpose:** Push summarized telemetry bundles from extractor to LLM.

### **/reason**
- **Method:** POST  
- **Purpose:** Request reasoning from the LLM based on telemetry and context.  
- **Returns:** summary, hypotheses, tests, recommendations, confidence.

### **/propose_action**
- **Method:** POST  
- **Purpose:** Submit a reasoning-based proposal to the policy engine.

Example:
```json
{
  "action": "config_change",
  "target": "plan-service",
  "param_diff": {"redis_ttl": {"from": 60, "to": 10}},
  "safety": {
    "canary": {"percent": 5, "duration": "15m"},
    "abort_if": {"latency_p99": ">0.3s"},
    "rollback": "redis_ttl=60"
  }
}
```

---

## 4. PromQL Query Catalog

All queries are pre-approved and versioned.

```yaml
- id: availability_by_service
  promql: >
    sum(rate(http_requests_total{status!~"5..",service="$service"}[$window])) /
    sum(rate(http_requests_total{service="$service"}[$window]))
  params: [service, window]

- id: latency_p99
  promql: >
    histogram_quantile(0.99,
      sum(rate(http_request_duration_seconds_bucket{service="$service"}[$window])) by (le))
  params: [service, window]
```

---

## 5. Security Boundaries

| Boundary | Enforcement |
|-----------|--------------|
| **Read Access** | Only summarized signals exposed to LLM. |
| **Query Execution** | Through controlled proxy; catalog-restricted. |
| **System Actions** | Policy Gate approval + human confirmation. |
| **Audit** | Logs every reasoning and decision hash-linked to metrics. |

---

## 6. Example Reasoning Session

1. Prometheus detects drop in API availability.  
2. Extractor posts summary to `/signals`.  
3. LLM Orchestrator analyzes via `/reason`.  
4. Suggests reverting recent Redis TTL change.  
5. Policy Gate requests confirmation before rollout.  

---

# End of Specification
