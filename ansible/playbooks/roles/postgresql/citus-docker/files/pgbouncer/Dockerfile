# Alpine-native PgBouncer (connection pooler in front of the Citus coordinator).
# aarch64-native — no amd64 dependency. Config is bind-mounted by compose at
# /etc/pgbouncer/pgbouncer.ini, so the image is just the binary + a non-root user.
FROM alpine:3.20

# The pgbouncer apk (unlike postgresql16) does not guarantee a system user we can
# rely on — create `pgbouncer` idempotently, then own the config/log/run dirs.
RUN apk add --no-cache pgbouncer su-exec \
 && (addgroup -S pgbouncer 2>/dev/null || true) \
 && (adduser -S -G pgbouncer -H -s /sbin/nologin pgbouncer 2>/dev/null || true) \
 && mkdir -p /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer \
 && chown -R pgbouncer:pgbouncer /etc/pgbouncer /var/log/pgbouncer /var/run/pgbouncer

EXPOSE 6432
USER pgbouncer
# Config comes from the bind-mounted ini (compose). exec form so signals reach pgbouncer.
ENTRYPOINT ["pgbouncer"]
CMD ["/etc/pgbouncer/pgbouncer.ini"]
