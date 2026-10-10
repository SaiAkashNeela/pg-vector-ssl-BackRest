# pgvector-ssl plus pgBackRest, for continuous WAL archiving and
# point-in-time recovery (to S3, R2, GCS, Azure or a local repository).
#
# Built FROM this repo's published pgvector-ssl image, so everything that
# image does (self-signed SSL, the vector extension enabled everywhere, tini
# as PID 1) is unchanged. This only adds:
#   pgbackrest  - from the image's own PGDG apt source, matching its Postgres
#   jq          - used by the backup loop to read `pgbackrest info` output
#   /usr/local/bin/pgbackrest-backup-loop.sh - optional base-backup scheduler
#
# pgBackRest is configured entirely through PGBACKREST_* environment
# variables; nothing is switched on by default. See README.md, "pgBackRest
# variant", for a working setup.
#
# Build (defaults to the PG 17 base):
#   docker build -f pgbackrest/Dockerfile -t pgvector-ssl-pgbackrest:17 pgbackrest
# Another Postgres major:
#   docker build -f pgbackrest/Dockerfile --build-arg PG_MAJOR=16 \
#     -t pgvector-ssl-pgbackrest:16 pgbackrest
ARG BASE_IMAGE=ghcr.io/saiakashneela/pgvector-ssl
ARG PG_MAJOR=17
FROM ${BASE_IMAGE}:pg${PG_MAJOR}

RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest jq \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o postgres -g postgres -m 750 /var/spool/pgbackrest /var/log/pgbackrest /var/lib/pgbackrest

COPY --chmod=755 pgbackrest-backup-loop.sh /usr/local/bin/pgbackrest-backup-loop.sh
