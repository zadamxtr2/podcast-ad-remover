# Versioning

Podcast Ad Remover uses Semantic Versioning in the form `MAJOR.MINOR.PATCH`.

The previous public release label `1.3` is treated as `1.3.0` from this point forward. Future releases should always include all three components.

## Version Source

- `package.json` is the primary version source.
- The root package entry in `package-lock.json` must match `package.json`.
- Docker releases are tagged with both the exact version and `latest`.

Example for version `1.3.0`:

```text
jdcb4/podcast-ad-remover:1.3.0
jdcb4/podcast-ad-remover:latest
```

## Bump Rules

- `PATCH`: bug fixes, documentation fixes, small internal improvements, and dependency updates that do not change user-visible behavior.
- `MINOR`: new features, new settings, new UI flows, additive API changes, and backward-compatible database migrations.
- `MAJOR`: breaking configuration changes, incompatible API changes, destructive storage changes, or database changes that cannot migrate existing installs automatically.

Because existing installs may have many downloaded podcasts, database and `/data` compatibility should be treated as release-critical.

## Release Checklist

1. Decide the next SemVer number.
2. Update `package.json` and `package-lock.json`.
3. Update `Documentation/CHANGELOG.md`.
4. Run local verification:

```bash
npm run verify
```

5. Run Docker verification:

```bash
npm run verify:docker
```

6. Publish the Docker image when ready:

```bash
npm run docker:publish
```

This builds and pushes `jdcb4/podcast-ad-remover:<version>` and `jdcb4/podcast-ad-remover:latest`.
