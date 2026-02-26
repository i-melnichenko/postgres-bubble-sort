#!/bin/sh
set -eu

PGDATA="${PGDATA:-/var/lib/postgresql/data}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-$POSTGRES_USER}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_HOST_AUTH_METHOD="${POSTGRES_HOST_AUTH_METHOD:-}"

docker_process_init_files() {
  for f in /docker-entrypoint-initdb.d/*; do
    [ -e "$f" ] || continue

    case "$f" in
      *.sh)
        if [ -x "$f" ]; then
          "$f"
        else
          . "$f"
        fi
        ;;
      *.sql)
        psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
        ;;
      *)
        echo "Ignoring init file: $f"
        ;;
    esac
  done
}

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$PGDATA"
  chown -R postgres:postgres "$(dirname "$PGDATA")"
  exec su-exec postgres "$0" "$@"
fi

mkdir -p "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  if [ -n "$POSTGRES_PASSWORD" ]; then
    auth_method="${POSTGRES_HOST_AUTH_METHOD:-scram-sha-256}"
    pwfile="$(mktemp)"
    trap 'rm -f "$pwfile"' EXIT
    printf '%s\n' "$POSTGRES_PASSWORD" > "$pwfile"
    initdb -D "$PGDATA" --username="$POSTGRES_USER" --pwfile="$pwfile" \
      --auth-local=trust --auth-host="$auth_method" --locale=C
    rm -f "$pwfile"
    trap - EXIT
  else
    auth_method="${POSTGRES_HOST_AUTH_METHOD:-trust}"
    initdb -D "$PGDATA" --username="$POSTGRES_USER" \
      --auth-local=trust --auth-host="$auth_method" --locale=C
  fi

  {
    echo "listen_addresses='*'"
    echo "unix_socket_directories='/tmp'"
  } >> "$PGDATA/postgresql.conf"

  {
    echo "host all all all $auth_method"
  } >> "$PGDATA/pg_hba.conf"

  pg_ctl -D "$PGDATA" -o "-c listen_addresses='' -c unix_socket_directories='/tmp'" -w start

  if [ "$POSTGRES_DB" != "postgres" ]; then
    createdb --username="$POSTGRES_USER" "$POSTGRES_DB"
  fi

  docker_process_init_files

  pg_ctl -D "$PGDATA" -m fast -w stop
fi

exec "$@" -D "$PGDATA"
