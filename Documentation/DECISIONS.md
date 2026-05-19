# Decisions

This is a lightweight decision log. Keep entries short, dated, and focused on choices that future maintainers may otherwise revisit.

## 2026-05-19: Keep SQLite and `/data` as the migration anchor

Existing users already have SQLite databases and downloaded podcast artifacts under `/data`. Improvements should preserve that layout unless there is a clear migration path, backup guidance, and a versioned release note.

## 2026-05-19: Publish Docker releases to Docker Hub

The release image is `jdcb4/podcast-ad-remover`. Every release should publish both a SemVer tag and `latest` so users can either pin a version or follow the current release.

## 2026-05-19: Use lightweight Python release scripts

The project is primarily Python, so verification and Docker publish helpers live in `scripts/` and are exposed through npm scripts. This keeps the commands easy to run on Windows and Linux while avoiding a larger build system.
