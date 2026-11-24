#!/bin/bash
# selfoss on Railway: prepare the data volume, lock the instance with a login,
# size Apache/PHP to the container, run Apache and the feed updater.
# Any unexpected stop exits non-zero so Railway's ON_FAILURE policy restarts the service.
set -euo pipefail

APP=/var/www/html
DATA=$APP/data
export PORT="${PORT:-8080}"
log() { echo "[selfoss-start] $*"; }
die() { echo "[selfoss-start] ERROR: $*" >&2; exit 1; }

# --- Login is mandatory: never serve an open instance on a public URL ---------
SELFOSS_USERNAME="${SELFOSS_USERNAME:-admin}"
[ -n "${SELFOSS_ADMIN_PASSWORD:-}" ] || die "SELFOSS_ADMIN_PASSWORD is empty; set it (the template generates one)."
[ "${#SELFOSS_ADMIN_PASSWORD}" -ge 8 ] || die "SELFOSS_ADMIN_PASSWORD must be at least 8 characters."
export SELFOSS_USERNAME
# selfoss compares against a hash; hash the plain password from the variable.
SELFOSS_PASSWORD="$(SELFOSS_ADMIN_PASSWORD="$SELFOSS_ADMIN_PASSWORD" php -r 'echo password_hash(getenv("SELFOSS_ADMIN_PASSWORD"), PASSWORD_DEFAULT);')"
export SELFOSS_PASSWORD
unset SELFOSS_ADMIN_PASSWORD

# --- Upstream advisory GHSA-2v57-rcgq-j44q: in selfoss <= 2.20 the strings
# "false"/"off"/"no" are read as TRUE for boolean options (so SELFOSS_PUBLIC=false
# would make the instance public). Normalise every boolean option to 0/1 first.
for opt in PUBLIC RSS_MARK_AS_READ AUTO_MARK_AS_READ AUTO_COLLAPSE AUTO_STREAM_MORE \
           OPEN_IN_BACKGROUND_TAB ALLOW_PUBLIC_UPDATE_ACCESS LOAD_IMAGES_ON_MOBILE \
           AUTO_HIDE_READ_ON_MOBILE SCROLL_TO_ARTICLE_HEADER SHOW_THUMBNAILS; do
  var="SELFOSS_$opt"
  [ -n "${!var+x}" ] || continue
  val="$(printf '%s' "${!var}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$val" in
    ""|0|false|off|no|n) export "$var=0" ;;
    1|true|on|yes|y) export "$var=1" ;;
    *) die "$var must be 0 or 1 (got '${!var}')." ;;
  esac
done
# selfoss also reads lower-case selfoss_* variables, which would skip the check above.
for v in $(env | grep -o '^selfoss_[a-z_]*' || true); do unset "$v"; done

# Logs go to Railway's log view instead of a file on the volume.
export SELFOSS_LOGGER_DESTINATION="${SELFOSS_LOGGER_DESTINATION:-error_log}"
export SELFOSS_LOGGER_LEVEL="${SELFOSS_LOGGER_LEVEL:-WARNING}"

# --- Data volume ---------------------------------------------------------------
mkdir -p "$DATA"
for d in cache favicons logs sqlite thumbnails fulltextrss sessions; do
  mkdir -p "$DATA/$d"
done
# Upstream's .htaccess/README files for the data folders (only if missing).
cp -rn /opt/selfoss-data-skeleton/. "$DATA/" 2>/dev/null || true
[ -f "$DATA/sessions/.htaccess" ] || echo "deny from all" > "$DATA/sessions/.htaccess"
find "$DATA" \( ! -user www-data -o ! -group www-data \) -exec chown www-data:www-data {} +
touch "$DATA/.write-test" && rm "$DATA/.write-test" || die "data volume $DATA is not writable"

# --- Size Apache and PHP to the container's memory and CPU ---------------------
mem_bytes=""
if [ -r /sys/fs/cgroup/memory.max ]; then mem_bytes="$(cat /sys/fs/cgroup/memory.max)"; fi
if [ -z "$mem_bytes" ] || [ "$mem_bytes" = "max" ]; then
  mem_bytes="$(awk '/MemTotal/ {print $2*1024}' /proc/meminfo)"
fi
mem_mb=$(( mem_bytes / 1024 / 1024 ))
cpus=1
if [ -r /sys/fs/cgroup/cpu.max ]; then
  read -r q p < /sys/fs/cgroup/cpu.max || true
  if [ "${q:-max}" != "max" ] && [ "${p:-0}" -gt 0 ]; then cpus=$(( (q + p - 1) / p )); else cpus="$(nproc)"; fi
fi
[ "$cpus" -ge 1 ] || cpus=1
# About 48 MB per Apache+PHP worker, 200 MB kept for the feed updater and the OS.
workers=$(( (mem_mb - 200) / 48 ))
[ "$workers" -ge 3 ] || workers=3
[ "$workers" -le $(( 8 * cpus )) ] || workers=$(( 8 * cpus ))
[ "$workers" -le 32 ] || workers=32
php_mem=128
[ "$mem_mb" -lt 1500 ] || php_mem=256
cli_mem=$(( php_mem * 2 ))
log "memory ${mem_mb} MB, ${cpus} CPU -> ${workers} Apache workers, PHP memory_limit ${php_mem}M (updater ${cli_mem}M)"

# Remove any MPM other than prefork (Railway can bring back mpm_event: AH00534).
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*
[ -e /etc/apache2/mods-enabled/mpm_prefork.load ] || a2enmod -q mpm_prefork >/dev/null
cat > /etc/apache2/mods-available/mpm_prefork.conf <<CONF
<IfModule mpm_prefork_module>
    StartServers            2
    MinSpareServers         1
    MaxSpareServers         3
    ServerLimit             ${workers}
    MaxRequestWorkers       ${workers}
    MaxConnectionsPerChild  500
</IfModule>
CONF

cat > /usr/local/etc/php/conf.d/zz-selfoss.ini <<INI
memory_limit = ${php_mem}M
expose_php = Off
display_errors = Off
log_errors = On
error_log = /proc/self/fd/2
upload_max_filesize = 16M
post_max_size = 16M
max_execution_time = 300
session.save_path = "${DATA}/sessions"
session.gc_maxlifetime = 2592000
session.cookie_httponly = 1
session.cookie_samesite = Lax
opcache.enable = 1
opcache.memory_consumption = 32
INI

echo "Listen ${PORT}" > /etc/apache2/ports.conf
apache2ctl -t >/dev/null 2>&1 || { apache2ctl -t; die "Apache configuration test failed"; }

# --- Create the database (and its tables) before serving ------------------------
cd "$APP"
runuser -u www-data -- env "PATH=$PATH" php -d "memory_limit=${cli_mem}M" -r '
  chdir("/var/www/html"); require "src/common.php";
  $dice->create(daos\DatabaseInterface::class);
  echo "[selfoss-start] database ready\n";' || die "database initialisation failed"

# --- Run Apache and the feed updater -----------------------------------------
INTERVAL_MIN="${SELFOSS_UPDATE_INTERVAL_MINUTES:-30}"
case "$INTERVAL_MIN" in ''|*[!0-9]*) die "SELFOSS_UPDATE_INTERVAL_MINUTES must be a whole number of minutes";; esac
[ "$INTERVAL_MIN" -ge 5 ] || INTERVAL_MIN=5

updater() {
  sleep 60
  while true; do
    # flock: never run two updates at once (a slow feed run can outlast the interval).
    if ! flock -n /tmp/selfoss-update.lock \
        runuser -u www-data -- env "PATH=$PATH" timeout 3000 php -d "memory_limit=${cli_mem}M" "$APP/cliupdate.php"; then
      echo "[selfoss-updater] feed update exited with an error (will retry next interval)" >&2
    fi
    sleep $(( INTERVAL_MIN * 60 ))
  done
}

apache_pid=""; updater_pid=""
stopping=0
shutdown() {
  stopping=1
  log "stopping"
  [ -n "$updater_pid" ] && kill "$updater_pid" 2>/dev/null || true
  [ -n "$apache_pid" ] && kill -WINCH "$apache_pid" 2>/dev/null || true
  sleep 1
  [ -n "$apache_pid" ] && kill -TERM "$apache_pid" 2>/dev/null || true
  wait 2>/dev/null || true
  exit 0
}
trap shutdown TERM INT

apache2-foreground &
apache_pid=$!
updater &
updater_pid=$!
log "selfoss 2.19 listening on port ${PORT}; feeds update every ${INTERVAL_MIN} min"

# Poll (BusyBox-style wait -n is unreliable); exit 1 if Apache dies unexpectedly.
while true; do
  if ! kill -0 "$apache_pid" 2>/dev/null; then
    [ "$stopping" = 1 ] && exit 0
    rc=0; wait "$apache_pid" 2>/dev/null || rc=$?
    echo "[selfoss-start] Apache stopped unexpectedly (exit $rc); exiting so Railway restarts the service" >&2
    kill "$updater_pid" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$updater_pid" 2>/dev/null; then
    echo "[selfoss-start] feed updater stopped; restarting it" >&2
    updater &
    updater_pid=$!
  fi
  sleep 5 & wait $! || true
done
