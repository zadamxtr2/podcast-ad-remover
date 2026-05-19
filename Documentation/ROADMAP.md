# Roadmap

This roadmap lists improvement candidates. It is not a release commitment.

## Reliability

- Add a real Python test suite around feed parsing, episode status transitions, RSS generation, and audio route authorization.
- Add migration tests that run against a copied `podcasts.db`.
- Move long-running processing into a more explicit job model with durable state and clearer retry semantics.

## Security

- Require a generated `SESSION_SECRET_KEY` in production rather than falling back to the development default.
- Consider tokenized feed and audio URLs for deployments exposed beyond a private network.
- Tighten admin/API authorization tests before adding more remote management features.

## Resource Usage

- Add documented concurrency and CPU guidance for small homelab machines.
- Make Whisper model choice, worker limits, cleanup policy, and retry settings easier to reason about from the UI.
- Add storage reporting for original audio, processed audio, transcripts, and models.

## User Experience

- Improve first-run setup for base URL, admin credentials, API keys, and recommended defaults.
- Add clearer queue state explanations for failed, rate-limited, ignored, and unprocessed episodes.
- Add safer backup/export guidance before upgrades.

## Maintainability

- Replace ad hoc schema migrations with explicit migration files.
- Split very large route and processor modules when tests are in place.
- Add CI that runs verification on pull requests.
