# postgres-ssl-pgvector

PostgreSQL with pgvector pre-installed, self-signed SSL baked in, and the
`vector` extension enabled automatically in every database. No `CREATE
EXTENSION`, no certificate wrangling — build, run, store embeddings.

Built `FROM` the official [`pgvector/pgvector`](https://hub.docker.com/r/pgvector/pgvector)
image, plus three standalone scripts. There are no other dependencies.

## The four images

| Image | What it is |
|---|---|
| `ghcr.io/saiakashneela/postgres-ssl` | Official PostgreSQL + self-signed SSL. No pgvector. |
| `ghcr.io/saiakashneela/postgres-ssl-pgbackrest` | `postgres-ssl` + [pgBackRest](#pgbackrest-variant) |
| `ghcr.io/saiakashneela/pgvector-ssl` | `postgres-ssl` + pgvector, enabled in every database |
| `ghcr.io/saiakashneela/pgvector-ssl-pgbackrest` | `pgvector-ssl` + pgBackRest |

All four share the same scripts, entrypoint and SSL handling, and are built
for every Postgres major in `PG_MAJORS`. `postgres-ssl` is built from
`postgres:<major>-bookworm` (the same base `pgvector/pgvector` uses); the
pgvector steps find no extension there and do nothing. Everything below about
`vector` applies to the `pgvector-ssl` images only.

## Features

- **pgvector out of the box.** The binaries come from the official image,
  and the extension is created for you — in `template1`, in the initial
  databases, and in every database you create later.
- **Self-signed SSL, always on.** A CA and server certificate are generated
  at initialization, `ssl` is enabled, and certificates renew themselves
  when they go missing or come within 30 days of expiry.
- **Both templates carry vector.** `template0` is rebuilt as a clone of the
  seeded `template1`, so it doesn't matter which template a `CREATE
  DATABASE` names — the extension is already there.
- **Self-healing.** On every boot a background pass recreates the extension
  wherever it's missing, moves outdated extension catalogs forward, and
  refreshes the `template0` clone when it drifts. It only logs when it
  actually changes something, and it can never fail your boot. No periodic
  loop: databases created later copy a template that already has vector.

## Quickstart

```bash
# pgvector 0.8.7 on PostgreSQL 17
docker build -f Dockerfile.pgvector -t postgres-ssl-pgvector:17 .

docker run -d --name pgvector \
  -e POSTGRES_PASSWORD=secret \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  postgres-ssl-pgvector:17
```

Connect with SSL enforced:

```bash
psql "host=localhost port=5432 dbname=postgres user=postgres password=secret sslmode=require"
```

## Storing embeddings

No setup step — `vector` already exists in every database, including ones
you create later from psql, `createdb`, or any IDE/GUI:

```sql
CREATE TABLE documents (
  id serial PRIMARY KEY,
  content text,
  embedding vector(3)
);

INSERT INTO documents (content, embedding) VALUES
  ('The Matrix', '[1,2,3]'),
  ('Inception',  '[1.1,2.1,2.9]'),
  ('Toy Story',  '[8,7,9]');

CREATE INDEX ON documents USING hnsw (embedding vector_l2_ops);

-- nearest neighbors to [1,2,3]
SELECT content
FROM documents
ORDER BY embedding <-> '[1,2,3]'
LIMIT 3;
```

## Configuration

| Variable | Purpose | Default |
|---|---|---|
| `POSTGRES_PASSWORD` | Superuser password (standard postgres var) | — |
| `POSTGRES_USER` / `POSTGRES_DB` | Superuser / initial database (standard postgres vars) | `postgres` |
| `SSL_CERT_DAYS` | Certificate validity period, in days | `820` |
| `PGVECTOR_AUTO_INSTALL_DISABLED=1` | Skip auto-enable and the `template0` upkeep (binaries stay installed; SSL unaffected) | off |

## Other versions

```bash
docker build -f Dockerfile.pgvector \
  --build-arg PGVECTOR_VERSION=0.8.7 --build-arg PG_MAJOR=18 \
  -t postgres-ssl-pgvector:18 .
```

Any `PGVECTOR_VERSION` × `PG_MAJOR` combo published under
`pgvector/pgvector` on Docker Hub works (e.g. `0.8.7-pg18`). Multi-arch
(`amd64` + `arm64`) via buildx:

```bash
docker buildx build -f Dockerfile.pgvector \
  --platform linux/amd64,linux/arm64 \
  -t postgres-ssl-pgvector:17 --push .
```

Plain postgres-ssl, from the same Dockerfile:

```bash
docker build -f Dockerfile.pgvector \
  --build-arg BASE_IMAGE=postgres:17-bookworm -t postgres-ssl:17 .
```

## Image tags

`ghcr.io/saiakashneela/pgvector-ssl` for every Postgres major listed in
`PG_MAJORS` (currently 16, 17 and 18):

- `0.8.7-pg17` — exact pgvector + Postgres major
- `pg17` — latest pgvector for that Postgres major, with the latest patches
- `latest` — latest pgvector on the default major (17)

`ghcr.io/saiakashneela/postgres-ssl`: `pg16`, `pg17`, `pg18` (latest patch
release of that major) and `latest` (the default major, 17). Pin by digest
for a fixed build.

Everything stays current on its own, with nothing to merge:

| When | Workflow | What it does |
|---|---|---|
| Every merge to main | `build-and-push.yml` | Rebuilds and republishes every tag of `pgvector-ssl` and `postgres-ssl`, then both pgBackRest variants |
| Sunday 02:30 UTC | `pgvector-bump.yml` | New pgvector release with images for every major we build → bumps the version, commits, rebuilds |
| Sunday 03:30 UTC | `postgres-major-check.yml` | Upstream has a newer Postgres major (say pg19) → adds it to `PG_MAJORS`, commits, rebuilds; new tags appear, existing ones are untouched |
| Monday 04:00 UTC | `build-and-push.yml` | Weekly rebuild from a fresh upstream base plus `apt-get upgrade`, so Postgres patch releases and Debian security fixes land every week |

The floating `pg<major>` tags therefore always carry the newest pgvector and
the newest patch release of that major. An exact tag such as `0.8.7-pg17`
keeps getting weekly patches only until pgvector moves on; after that it is
frozen, so prefer `pg<major>` if you want patches without editing tags.
Changing the default major (`latest`) is left to a person.

## pgBackRest variant

`ghcr.io/saiakashneela/pgvector-ssl-pgbackrest` and
`ghcr.io/saiakashneela/postgres-ssl-pgbackrest` are the base images plus
[pgBackRest](https://pgbackrest.org) and `jq`, for continuous WAL archiving and
point-in-time recovery. Tags mirror their base image (`0.8.7-pg16` for
pgvector only, `pg16`, …, `latest`), and they are rebuilt every time the base
images are republished. The setup below is the same for both.

Nothing is switched on by default; configure pgBackRest with `PGBACKREST_*`
environment variables and turn archiving on in the server command. An example
with Cloudflare R2:

```yaml
services:
  postgres:
    image: ghcr.io/saiakashneela/pgvector-ssl-pgbackrest:pg16
    environment:
      POSTGRES_PASSWORD: change-me
      PGBACKREST_STANZA: main
      PGBACKREST_PG1_PATH: /var/lib/postgresql/data
      PGBACKREST_REPO1_TYPE: s3
      PGBACKREST_REPO1_PATH: /pgbackrest
      PGBACKREST_REPO1_S3_BUCKET: my-bucket
      PGBACKREST_REPO1_S3_ENDPOINT: <account>.r2.cloudflarestorage.com
      PGBACKREST_REPO1_S3_REGION: auto
      PGBACKREST_REPO1_S3_URI_STYLE: path
      PGBACKREST_REPO1_S3_KEY: ...
      PGBACKREST_REPO1_S3_KEY_SECRET: ...
      PGBACKREST_REPO1_RETENTION_FULL: "2"
      PGBACKREST_ARCHIVE_ASYNC: "y"
      PGBACKREST_SPOOL_PATH: /var/spool/pgbackrest
      PGBACKREST_BACKUP_HOUR: "21"   # UTC hour for scheduled base backups
    command: postgres -c archive_mode=on -c archive_timeout=60 -c "archive_command=pgbackrest archive-push %p"
```

Start the included scheduler beside the server, as the `postgres` user, for
fresh base backups (a full one weekly, a differential on other days, only in
`PGBACKREST_BACKUP_HOUR`; the very first one starts at once):

```bash
docker exec -d -u postgres <container> /usr/local/bin/pgbackrest-backup-loop.sh
```

| File | Does |
|---|---|
| `pgbackrest/Dockerfile` | This image on top of `pgvector-ssl:pg<major>`: `pgbackrest`, `jq`, the scheduler |
| `pgbackrest/pgbackrest-backup-loop.sh` | Creates the stanza once Postgres is up, then keeps base backups fresh. Reads backup age from the repository, so restarts neither skip nor repeat backups |

Useful commands: `pgbackrest info`, `pgbackrest check`, and
`pgbackrest --type=time "--target=<UTC time>" restore` into a stopped,
emptied data directory.

## How it works

| File | Runs | Does |
|---|---|---|
| `Dockerfile.pgvector` | build | Official pgvector base + `openssl`/`tini` + the scripts below |
| `ssl-init.sh` | once, at initdb | Generates the CA + server cert, enables `ssl` |
| `init-pgvector.sh` | once, at initdb | Creates `vector` in `template1`/`postgres`/`$POSTGRES_DB`, rebuilds `template0` as a clone |
| `wrapper-pgvector.sh` | every boot (entrypoint) | Regenerates expiring certs, starts a background pass (once per boot) that ensures the extension and the `template0` clone, then hands off to the official entrypoint |

Certificate state and the clone stamp live alongside the data so they
survive restarts: certs in `$PGDATA/certs`, the clone version in
`$PGDATA/.pgvector_template0_clone`.

## License

MIT — see [LICENSE](LICENSE).
