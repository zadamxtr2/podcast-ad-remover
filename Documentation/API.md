# AI API

Podcast Ad Remover exposes an optional REST API for AI agents and automation clients under `/api/v1`.

The API is disabled by default. Admins enable it from **Admin > System Settings > AI API**, configure default rate limits, and create bearer tokens from the same page.

## Authentication

All management endpoints require:

```http
Authorization: Bearer par_...
```

API tokens are separate from feed tokens. Feed tokens only grant podcast feed/audio access, while API tokens grant management actions. The app stores only SHA-256 token hashes and shows the full token only once during creation.

Available scopes:

| Scope | Allows |
|-------|--------|
| `read` | Read subscriptions, episodes, queue state, transcripts, reports, and search results. |
| `write` | Add subscriptions and update podcast settings. |
| `process` | Trigger checks, downloads, reprocessing, cancellation, and ignore actions. |
| `admin` | Read instance-level system status. |

## Rate Limits

Rate limits are stored in SQLite and survive app restarts.

- Authenticated requests are limited by API token.
- Missing or invalid token attempts are limited by client IP.
- `429` responses include `Retry-After`.

When `TRUST_PROXY_HEADERS=true`, the app uses trusted reverse-proxy headers for the client IP. Only enable that setting behind a proxy that strips client-supplied forwarded headers.

## Discovery

When the API is enabled:

| Method | Path | Auth |
|--------|------|------|
| `GET` | `/api/v1/health` | none |
| `GET` | `/api/v1/capabilities` | none |
| `GET` | `/api/v1/openapi.json` | none |

`/api/v1/health` remains available when disabled and reports `enabled: false`.

## Endpoints

Read endpoints require `read` unless noted:

| Method | Path | Scope |
|--------|------|-------|
| `GET` | `/api/v1/system/status` | `admin` |
| `GET` | `/api/v1/queue` | `read` |
| `GET` | `/api/v1/subscriptions` | `read` |
| `GET` | `/api/v1/subscriptions/{id}` | `read` |
| `GET` | `/api/v1/subscriptions/{id}/episodes` | `read` |
| `GET` | `/api/v1/episodes/{id}` | `read` |
| `GET` | `/api/v1/episodes/{id}/transcript` | `read` |
| `GET` | `/api/v1/episodes/{id}/report` | `read` |
| `POST` | `/api/v1/search` | `read` |
| `POST` | `/api/v1/subscriptions` | `write` |
| `PATCH` | `/api/v1/subscriptions/{id}/settings` | `write` |
| `POST` | `/api/v1/subscriptions/{id}/check` | `process` |
| `POST` | `/api/v1/episodes/{id}/download` | `process` |
| `POST` | `/api/v1/episodes/{id}/reprocess` | `process` |
| `POST` | `/api/v1/episodes/{id}/cancel` | `process` |
| `POST` | `/api/v1/episodes/{id}/ignore` | `process` |

Hard global podcast deletion is intentionally not exposed in API v1.

## Example

```bash
curl -H "Authorization: Bearer par_REPLACE_ME" \
  http://localhost:8000/api/v1/subscriptions
```
