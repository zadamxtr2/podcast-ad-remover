# Deployment

Docker is the recommended deployment path.

## Docker Run

```bash
docker run -d \
  --name podcast-ad-remover \
  -p 8000:8000 \
  -v ./data:/data \
  -e GEMINI_API_KEY=your_key_here \
  -e BASE_URL=http://your-server-ip:8000 \
  jdcb4/podcast-ad-remover:latest
```

For a production install, also set a unique `SESSION_SECRET_KEY`.
If users access the app through HTTPS behind a reverse proxy, set `COOKIE_SECURE=true`.
Only set `TRUST_PROXY_HEADERS=true` when that proxy strips any client-supplied forwarding headers before passing requests to the app.
For authenticated management access behind a reverse proxy, set `BASE_URL` or the System Settings public application URL to the browser-facing origin so same-origin checks accept legitimate form submissions.

## Docker Compose

Use `docker-compose.prod.yml` and the published image when running a normal install:

```yaml
services:
  app:
    image: jdcb4/podcast-ad-remover:latest
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - ./data:/data
    environment:
      - GEMINI_API_KEY=your_key_here
      - BASE_URL=http://your-server-ip:8000
      - SESSION_SECRET_KEY=replace-with-a-long-random-secret
      - LOG_LEVEL=INFO
```

Start it with:

```bash
docker compose -f docker-compose.prod.yml up -d
```

The repository `docker-compose.yml` is intended for local source builds and development. It bind-mounts the source tree into `/app`; do not use that file for a stable install unless you intentionally want live source edits inside the container.

## Data Volume

Mount `/data` and back it up before upgrades.

Important paths:

- `/data/db/podcasts.db`: SQLite database.
- `/data/podcasts/`: podcast and episode artifacts.
- `/data/feeds/`: generated RSS files.
- `/data/models/`: downloaded local model files.
- `/data/app.log`: application log.

Do not delete `/data` unless you intentionally want to remove the app database and downloaded podcasts.

## Building From Source

```bash
docker compose up -d --build
```

For a local image without Compose:

```bash
docker build -t podcast-ad-remover:local .
```

## Release Publishing

Before upgrading an existing install with important data, dry-run database migrations against a copy:

```bash
npm run db:migration-dry-run -- --db-path /path/to/data/db/podcasts.db
```

The command copies the database to a temporary data directory and runs the normal startup migration path there without modifying the source database.

Before publishing:

```bash
npm run verify:docker
```

To publish the current version from `package.json`:

```bash
npm run docker:publish
```

This pushes both:

- `jdcb4/podcast-ad-remover:<version>`
- `jdcb4/podcast-ad-remover:latest`
