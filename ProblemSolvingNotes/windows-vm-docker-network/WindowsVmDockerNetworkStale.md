# Windows VM Docker Networking: Stale Network Reference

**Date:** 2026-06-30
**Files:**

- Docker compose project for the Windows VM (container `omarchy-windows`)

## Problem

Launching the Windows VM container fails with a networking error after the
compose network was recreated.

## Symptoms

```
failed to set up container networking: network windows_default ... not found
```

- The compose network exists but the container references a stale network ID

## Investigation

Docker networks get a new ID each time they are recreated. A container created
against the *old* network ID keeps referencing it; once that network is gone the
container can no longer start.

### Root Cause

Compose network (`windows_default`) was recreated, but the existing container
still points at the previous network ID.

## Solution

```bash
docker rm omarchy-windows
# then launch fresh
docker compose up -d
```

## Verification

- Container starts and attaches to the current network
- No `network ... not found` error

## Notes

- `docker rm` (not `-f`) is enough when the container is stopped/failed.
- When debugging, `docker inspect <container> | grep -i network` shows the stale
  ID reference.
