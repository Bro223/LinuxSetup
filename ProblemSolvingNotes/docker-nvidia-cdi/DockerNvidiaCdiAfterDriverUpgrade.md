# Docker GPU Containers Fail After NVIDIA Driver Upgrade (CDI)

**Date:** 2026-08-17
**Files:**

- `/etc/cdi/nvidia.yaml` — CDI spec, hard-codes driver lib paths
- `docker compose` GPU services

## Problem

After a host NVIDIA driver upgrade, Docker containers requesting GPU devices fail
to start.

## Symptoms

```
failed to fulfil mount request: open /usr/lib/libEGL_nvidia.so.<oldver>: no such file
```

- Same error for other `libnvidia-*` / `libEGL_nvidia.so.*` paths
- The compose service shows `Created` then fails on start

## Investigation

GPU device requests resolve via the **CDI spec** `/etc/cdi/nvidia.yaml`
(no `nvidia` runtime in `daemon.json`). When the driver is upgraded, the new
driver ships new library versions, but the CDI spec still references the old
paths — so the mount request points at files that no longer exist.

### Root Cause

Stale CDI spec generated for the previous driver version. Driver upgrade:
580.159.04 → 580.178.04 (Aug 2026).

## Solution

```bash
# 1. Regenerate the CDI spec for the current driver
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# 2. Remove the stale failed container
docker rm <container>

# 3. Bring the service back up
docker compose up -d
```

## Verification

- `docker compose up -d` starts cleanly
- Container reports the GPU (`nvidia-smi` inside the container)
- `/etc/cdi/nvidia.yaml` references the current driver version

## Notes

- Re-run this after **every** host NVIDIA driver upgrade.
- CDI is the modern path (container-toolkit style) — there is no
  `nvidia` runtime in `daemon.json` on this machine.
