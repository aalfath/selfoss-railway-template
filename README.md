[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/selfoss?utm_medium=integration&utm_source=button&utm_campaign=selfoss)

# selfoss on Railway

One-click [selfoss](https://selfoss.aditu.de) (RSS reader and feed aggregator, GPL-3.0) for [Railway](https://railway.com).

**Version:** selfoss **2.19**, the latest stable release, built from the official release zip (checked against its sha256) on the official `php:8.2.36-apache-bookworm` image, pinned by digest. Upstream doesn't publish a Docker image of its own.

## What you get

One service, `selfoss`:

- Apache + PHP 8.2 serving selfoss on Railway's `PORT`, with a public Railway domain and a health check on `/api/about`.
- A Railway volume at `/var/www/html/data` holding the SQLite database, favicons, thumbnails and login sessions, so everything survives redeploys and restarts.
- A built-in feed updater that fetches all sources every 30 minutes (`SELFOSS_UPDATE_INTERVAL_MINUTES`), so you don't need a cron service.
- Login always on, with a generated password. The service refuses to start without one, so the instance is never open to the public.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `SELFOSS_USERNAME` | `admin` | Login name. |
| `SELFOSS_ADMIN_PASSWORD` | generated (`${{secret(24)}}`) | Login password, at least 8 characters. Change it in the service's variables and redeploy. |
| `PORT` | `8080` | Port Apache listens on. |

Optional, not set by the template: any [selfoss option](https://selfoss.aditu.de/docs/administration/options/) as an upper-case `SELFOSS_<OPTION>` variable, for example `SELFOSS_ITEMS_LIFETIME=60`, `SELFOSS_LANGUAGE=de` or `SELFOSS_UPDATE_INTERVAL_MINUTES=15`. Boolean options take `0` or `1` (`true`/`false` also work in this template).

## After deploying

1. Open the Railway domain and sign in as `admin` with `SELFOSS_ADMIN_PASSWORD` (Service → Variables).
2. Go to the settings (the gear icon) and add feeds, or import an OPML file at `/opml`.
3. New items appear after the next update run (within 30 minutes), or click "Refresh" for an update now.

## Memory

It runs on Railway's 0.5 GB / 1 vCPU plan: the start script sizes Apache workers and PHP's memory limit from the container's limits. Larger plans get more workers.

## Updates

This template builds from this repository. When `main` changes (for example a new selfoss release), Railway shows deployers an "update available" notice, and you choose when to apply it. Read [`CHANGELOG.md`](CHANGELOG.md) first: breaking changes are listed first. Your data stays on the volume across updates.

## Files

- `Dockerfile`: the pinned PHP image, the selfoss release zip and GD.
- `start.sh`: prepares the volume, hashes the password, sizes Apache/PHP, runs Apache and the feed updater, and exits non-zero if Apache stops so Railway restarts it.
- `apache-selfoss.conf`: Apache virtual host on `PORT`, HTTPS detection behind Railway's proxy, and deny rules for the data folder.

selfoss is © its authors, licensed under GPL-3.0. This wrapper is maintained by Heron Technology.
