# 🌐 DNS Subsystem

The DNS module embeds an authoritative name server directly into the gateway. It manages zones on disk, keeps an in-memory cache, and serves signed responses over UDP or TCP.

![image_gen: Architecture diagram showing ZoneManager feeding records to DNSEngine which responds through DNSServer]

## Components

### ZoneManager
- `actor` responsible for persisting zone data in `Configuration/zones.yml`.
- Emits an `AsyncStream` of flattened records and watches the YAML file for changes.

### DNSEngine
- Maintains a thread-safe cache of `A`, `AAAA`, `CNAME`, `MX`, `TXT`, `SRV`, and `CAA` records.
- Answers queries via `handleQuery` and refreshes its cache from `ZoneManager.updates`.
- Optionally signs and verifies zones using `DNSSECSigner`.

### DNSServer
- SwiftNIO server that binds UDP (default `1053`) and optionally TCP listeners.
- Each channel installs a `DNSHandler` that hands raw datagrams to the engine and writes responses.

### DNSHandler
- Translates between `ByteBuffer` packets and `DNSMessage` structures.
- Delegates lookups to the engine and serializes replies.

### DNSSECSigner
- Loads a private key and DS record to produce RRSIGs for supported records.
- Verification can be enabled to reject tampered zones.

### DNSMetrics
- Exposes Prometheus-style counters and gauges for query totals, failures, and cache size.

## Configuration

Zones are stored in `Configuration/zones.yml`:

```yaml
zones:
  example.com:
    records:
      - type: A
        name: example.com
        value: 192.0.2.1
```

Updating the YAML file triggers `ZoneManager` to reload and publish the new snapshot.

## Running the server

The gateway executable can launch DNS alongside HTTP:

```bash
$ swift run GatewayApp --dns
```

- Zone data is loaded from `Configuration/zones.yml`.
- UDP port `1053` is opened for queries; adjust the call to `dns.start` to change ports.

## Control plane API

The HTTP gateway exposes endpoints that delegate to `ZoneManager`:
The full API specification is defined in [`openapi/v1/dns.yml`](../../openapi/v1/dns.yml).

- `GET  /zones` – list all zones
- `POST /zones` – create a new zone
- `DELETE /zones/{id}` – remove a zone
- `GET  /zones/{id}/records` – list records
- `POST /zones/{id}/records` – add a record
- `PUT  /zones/{id}/records/{rid}` – update a record
- `DELETE /zones/{id}/records/{rid}` – delete a record

These routes allow dynamic management of DNS data without editing the YAML file directly.

## Metrics

DNS-specific metrics are merged into the gateway's `/metrics` endpoint, enabling scraping by systems like Prometheus.

---
© 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
