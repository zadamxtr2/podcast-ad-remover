# Decisions

This is a lightweight decision log. Keep entries short, dated, and focused on choices that future maintainers may otherwise revisit.

## 2026-05-19: Keep SQLite and `/data` as the migration anchor

Existing users already have SQLite databases and downloaded podcast artifacts under `/data`. Improvements should preserve that layout unless there is a clear migration path, backup guidance, and a versioned release note.

## 2026-05-19: Publish Docker releases to Docker Hub

The release image is `jdcb4/podcast-ad-remover`. Every release should publish both a SemVer tag and `latest` so users can either pin a version or follow the current release.

## 2026-05-19: Use lightweight Python release scripts

The project is primarily Python, so verification and Docker publish helpers live in `scripts/` and are exposed through npm scripts. This keeps the commands easy to run on Windows and Linux while avoiding a larger build system.

## 2026-06-11: Keep public subscription access optional and unauthenticated by default

The main workflow is subscribing from podcast clients, many of which handle authentication inconsistently. Dashboard management can require login, while the public subscribe page and feeds remain unauthenticated unless feed authentication is explicitly enabled.

## 2026-06-11: Keep SQLite as the default database for this audit pass

The target deployment is a personal Docker install with existing SQLite data under `/data`. The audit branch improves SQLite safety with WAL, a longer busy timeout, migration backups, and durable job rows rather than introducing a database migration to a larger service.

## 2026-06-11: Improve the current FastAPI/Jinja app incrementally before considering a rebuild

The current app has oversized modules and templates, but the core architecture still matches the deployment model. The audit branch should reduce risk through tests, auth hardening, resource controls, and focused refactors before considering a full frontend or backend rebuild.
