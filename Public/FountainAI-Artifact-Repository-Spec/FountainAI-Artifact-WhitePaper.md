# FountainAI Artifact & Model Repository White Paper

## Abstract
This white paper describes the architecture and rationale of the FountainAI Artifact & Model Repository system. 
It defines a unified interface for model metadata management and artifact storage, integrating FountainStore as the persistent layer and MinIO as the S3-compatible backend. The design allows seamless integration with FountainAI’s Patchbay experimentation environment and ensures reproducible, immutable model storage.

## Core Principles
1. **OpenAPI-first** – API definitions are canonical, ensuring language-agnostic interoperability.
2. **Digest-addressed storage** – All objects are addressed by SHA-256 digests for immutability.
3. **Provider-agnostic architecture** – Works with MinIO, AWS S3, B2, or any S3-compatible backend.
4. **Declarative persistence** – FountainStore, not SQL, is the authoritative record of truth.
5. **End-to-end provenance** – Every artifact includes creation metadata, license, and lineage links.

## Architecture Overview
The system comprises two main components:
- **Artifact Service**: manages binary assets (e.g., model checkpoints) and presigned URLs for upload/download.
- **Model Registry Service**: stores structured model metadata and links to artifacts.

FountainStore acts as the metadata and envelope persistence layer, while MinIO stores binary data. A scheduled backup route synchronizes both FountainStore and artifact blobs to an external S3 target for redundancy.

## Backup and Redundancy
All artifacts and FountainStore corpora are backed up periodically to an external S3 endpoint (AWS, B2, Wasabi, etc.).
Each backup job is registered and tracked in FountainStore. Data integrity is verified using SHA-256 digests before sync.

## Security
- Role-based API tokens control upload, download, and backup permissions.
- Pre-signed URLs ensure temporary, scoped access to model artifacts.
- HTTPS enforcement via reverse proxy and optional mTLS between internal services.

## Example Data Flow
1. A developer registers a new model version via `/models`.
2. The system creates a pre-signed PUT URL under `/artifacts`.
3. The uploaded binary is stored in MinIO and verified by digest.
4. The ModelRegistry entry is updated to reference the artifact.
5. A nightly `/backups/s3/sync` route mirrors artifacts + metadata to external S3 storage.

## Implementation Highlights
- **Server Framework**: Swift 6 (OpenAPI Generator Plugin)
- **Persistence**: FountainStore corpus, content-addressed JSON envelopes.
- **Storage Backend**: MinIO (S3 API compatible)
- **Security**: JWT or API key auth, scoped pre-signed URLs.
- **Backup Sync**: Cron or background Swift task invoking `/backups/s3/sync`

