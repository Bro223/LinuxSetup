# mvn test fails: Testcontainers vs Docker minimum API version (1.32 pinned vs 1.40 required)

**Project:** OpenShelter (`/home/aleks/MyScripts/LocalRepos/OpenShelter`)
**Date:** 2026-08-25
**Status:** FIXED — Testcontainers upgraded 1.21.3 → 2.0.5

---

## Symptom

`mvn test` fails. All **unit** tests pass; every **integration test** that uses
Testcontainers (to spin up a throwaway `postgres:16` container) fails:

```
[ERROR] ee.sheltermap.api.ShelterApiE2EIT ... <<< ERROR!
java.lang.ExceptionInInitializerError
Caused by: java.lang.IllegalStateException: Could not find a valid Docker environment.
[ERROR] ee.sheltermap.api.ShelterApiIT ... <<< ERROR!  (16 errors)
java.lang.NoClassDefFoundError: Could not initialize class ee.sheltermap.persistence.AbstractPersistenceIT
```

The interesting bit in the log:

```
UnixSocketClientProviderStrategy: failed with exception BadRequestException
(Status 400: {"message":"client version 1.32 is too old. Minimum supported API version is 1.40, please upgrade your client to a newer version"})
```

## Environment

| Thing | Value |
|---|---|
| Docker daemon | 29.7.2 (`docker version` → "API version: 1.55 (minimum version 1.40)") |
| Docker socket | `/var/run/docker.sock`, systemd socket-activated, daemon runs fine |
| Testcontainers (pinned) | 1.21.3 (docker-java 3.4.2, shaded into the TC jar) |
| Java / Spring Boot | 21 / 3.3.13 |

## Root cause

**Testcontainers 1.21.3 hardcodes Docker API version 1.32 when it cannot
auto-detect the daemon's version, and Docker ≥ some version (here 29.7.2)
rejects API < 1.40.**

1. `Testcontainers 1.21.3` `DockerClientProviderStrategy.getClientForConfig()`
   (confirmed by decompiling the jar):
   ```java
   if (config.getApiVersion() == UNKNOWN_VERSION) {
       builder.withApiVersion(VERSION_1_32);   // blind pin to 1.32
   }
   ```
2. docker-java then sends the version in the **URL path**: `GET /v1.32/_ping`.
3. The daemon answers `HTTP 400 {"message":"client version 1.32 is too old.
   Minimum supported API version is 1.40, ..."}`.
4. `UnixSocketClientProviderStrategy` → 400; `DockerDesktopClientProviderStrategy`
   → NPE. Testcontainers concludes "Could not find a valid Docker environment"
   → `ExceptionInInitializerError` in `AbstractPersistenceIT.<clinit>` →
   `NoClassDefFoundError` for every IT inheriting from it.

Docker itself works fine from the CLI — the CLI negotiates to 1.55. Only
docker-java's pinned 1.32 hits the floor.

### Evidence / debugging trail

- Captured the exact exchange with a unix-socket relay probe (Java, same jars):
  ```
  GET /v1.32/_ping HTTP/1.1
  HTTP/1.1 400 Bad Request
  {"message":"client version 1.32 is too old. Minimum supported API version is 1.40, please upgrade your client to a newer version"}
  ```
- Gotcha: the daemon does **NOT** enforce the minimum via the `Api-Version`
  header on unversioned paths (`/version`, `/info`, `/containers/create` all
  return 200 with header `Api-Version: 1.32`). It only rejects the versioned
  `/v1.x/...` URL path. So curl header tests do NOT reproduce the failure —
  you must test the versioned path.
- Bytecode proof of the 1.32 pin: `getClientForConfig` shows
  `if_icmpeq`/`getstatic VERSION_1_32` + `withApiVersion(...)`.
- Testcontainers 2.0.5 bytecode comparison: now logs "Pinging Docker API
  version 1.44." and only falls back to 1.32 if that probe fails.

## Fix (applied)

Upgraded Testcontainers in `pom.xml`:

```xml
<properties>
    <testcontainers.version>2.0.5</testcontainers.version>
</properties>
```

Note: Testcontainers 2.0 **renamed its module artifacts** with a
`testcontainers-` prefix — the dependency coordinates must change too:

```xml
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>testcontainers-junit-jupiter</artifactId>   <!-- was junit-jupiter -->
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>testcontainers-postgresql</artifactId>      <!-- was postgresql -->
    <scope>test</scope>
</dependency>
```

Test code needed **no changes** — only the stable APIs are used
(`PostgreSQLContainer`, `@SpringBootTest`, `DynamicPropertySource`).

## Alternative (temporary) workaround

If you cannot upgrade Testcontainers, force a modern API version:

```bash
mvn test -Dapi.version=1.43        # any value 1.40..1.55 works
```

or permanently in the surefire plugin:

```xml
<configuration>
    <systemPropertyVariables>
        <api.version>1.43</api.version>
    </systemPropertyVariables>
</configuration>
```

The shaded docker-java inside Testcontainers reads the `api.version` **system
property** (NOT a `DOCKER_API_VERSION` env var — that one is ignored).

## Verification

- `mvn test` (plain, no workaround flags): **169 tests, 0 failures, 0 errors —
  BUILD SUCCESS** ✅
- Previously failing classes now green: `ShelterApiIT` 16/16, `ShelterApiE2EIT` 1/1.
- `mvn dependency:tree` confirms all testcontainers modules resolve to 2.0.5.

## Reusable takeaways

1. If Testcontainers ITs suddenly fail with "client version 1.32 is too old",
   it means the pinned 1.21.3-era fallback hits a daemon whose minimum API is
   ≥ 1.40. Upgrade Testcontainers (≥ 2.0.5) or set `-Dapi.version=<1.40..1.55>`.
2. When upgrading Testcontainers 1.x → 2.x, rename artifacts:
   `junit-jupiter` → `testcontainers-junit-jupiter`, `postgresql` →
   `testcontainers-postgresql` (all modules got the prefix).
3. To debug docker-java/Testcontainers against a docker socket, a unix-socket
   relay probe (Java `StandardProtocolFamily.UNIX`) is the fastest way to see
   the raw request/response bytes.
