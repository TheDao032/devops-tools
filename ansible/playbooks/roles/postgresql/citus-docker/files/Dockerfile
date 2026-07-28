# Alpine-native Citus node image (coordinator + workers share one image).
#
# WHY Alpine and not the usual apt/citusdata path: the citusdata apt repo
# (install.citusdata.com) and the official citusdata/citus Docker image are BOTH
# amd64-only — verified 2026-07-28 (0 arm64 debs in bookworm/bullseye; image tags
# 12.1/13.0/latest are linux/amd64). k3s-lb is Arch Linux ARM64 (aarch64), so the
# only NATIVE Citus for this host is Alpine's `postgresql-citus` package, which in
# v3.20/community ships citus 12.1.3 built against postgresql16 (aarch64). See
# 40-decisions/2026-07-28-citus-arm64-alpine-dockerized.md.
#
# Layout discovered empirically in alpine:3.20 (do NOT assume Debian paths):
#   binaries: /usr/bin/{postgres,initdb,psql,pg_ctl,pg_isready} -> /usr/libexec/postgresql/
#   pkglibdir: /usr/lib/postgresql16  (citus.so lives here — matches shared_preload_libraries)
#   extension control: /usr/share/postgresql16/extension/citus.control
#   no default PGDATA (must pass -D or set $PGDATA); `postgres` user preexists.
FROM alpine:3.20

# su-exec = Alpine's gosu (drop root -> postgres). tzdata for sane timestamps.
RUN apk add --no-cache postgresql16 postgresql16-contrib postgresql-citus su-exec tzdata

ENV PGDATA=/var/lib/postgresql/data \
    LANG=C.UTF-8

# Socket dir + data dir owned by postgres. The data dir is a mount point at runtime
# (named volume) — the entrypoint re-chowns it as root before dropping privileges.
RUN mkdir -p "$PGDATA" /run/postgresql \
 && chown -R postgres:postgres /var/lib/postgresql /run/postgresql

COPY node-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5432
# Entrypoint runs as ROOT (to fix volume ownership) then su-exec's to postgres.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["postgres"]
