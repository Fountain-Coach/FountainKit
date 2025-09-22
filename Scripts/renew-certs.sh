#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
CERT_DIR="$REPO_ROOT/Configuration/certs"
mkdir -p "$CERT_DIR"

echo "[certs] Generating placeholder development certificates in $CERT_DIR" >&2
cat <<PEM > "$CERT_DIR/server.pem"
-----BEGIN CERTIFICATE-----
MIIBszCCAVmgAwIBAgIJAO6dummy0001MAoGCCqGSM49BAMCMBUxEzARBgNVBAMM
CmZvdW50YWluLWRldjAeFw0yNTAxMDEwMDAwMDBaFw0yNjAxMDEwMDAwMDBaMBUx
EzARBgNVBAMMCmZvdW50YWluLWRldjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IA
BKWxV+gSOn79rJ1smp1eb4cM9yap8PLRrWcmHYyY0uYzNPf1paNT6KTndciSyuP1
JH1HdFGWEfUuV5IOr0NF9bOjUzBRMB0GA1UdDgQWBBQJbngRp8uq3pWmY1xVEnbW
F5K2ajAfBgNVHSMEGDAWgBQJbngRp8uq3pWmY1xVEnbWF5K2ajAPBgNVHRMBAf8E
BTADAQH/MAoGCCqGSM49BAMCA0gAMEUCIQCTHhVw0l5qfLxyS1Y5i5DJ/S1BU1XO
4i9p7KqwCL90rQIgV2A9Pl5eZZdM6kBIKagJZCR5MdScdeXM6bK6CiPJ4WY=
-----END CERTIFICATE-----
PEM

echo "[certs] Stub certificate refreshed" >&2
