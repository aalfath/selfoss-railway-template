# Deploy and Host selfoss on Railway

selfoss is an open-source RSS reader and feed aggregator written in PHP. It collects articles from RSS and Atom feeds, YouTube channels, Reddit, GitHub and other sources into one fast web interface with tags, starring, search, keyboard shortcuts, OPML import and export, and a JSON API used by mobile apps.

## About Hosting selfoss

This template runs selfoss 2.19, the latest stable release, as a single service built from our GitHub repository. Upstream publishes no Docker image, so the repository builds the official release zip (checked against its sha256) on the official PHP 8.2 Apache image, pinned by digest. A Railway volume holds the SQLite database, favicons, thumbnails and login sessions, so nothing is lost on a redeploy or restart. A built-in updater fetches every feed every 30 minutes, so no cron service is needed. The login is always on, with a generated password, and the service won't start without one. It fits Railway's 0.5 GB plan.

## Common Use Cases

* Follow news sites, blogs and podcasts in one private, ad-free reader
* Track GitHub releases and commits, YouTube channels and subreddits as feeds
* Replace a hosted reader such as Feedly or Inoreader with one you control, and sync it to mobile apps through its API

## Dependencies for selfoss Hosting

* One Railway service built from `aalfath/selfoss-railway-template` (Apache + PHP 8.2 + selfoss 2.19)
* One Railway volume at `/var/www/html/data` for the SQLite database and caches

### Deployment Dependencies

* selfoss: https://github.com/fossar/selfoss
* Documentation and options: https://selfoss.aditu.de/docs/administration/options/
* Template repository: https://github.com/aalfath/selfoss-railway-template

### Implementation Details

**Services:** `selfoss` (the web app, the feed updater and the SQLite database, in one container with its volume). The template asks no questions.

**After deploying:**

1. Open the service's Railway domain and sign in as `admin` with the password in the `SELFOSS_ADMIN_PASSWORD` variable (Service, then Variables).
2. Open the settings (gear icon) to add feeds, or import an OPML file at `https://YOUR-DOMAIN/opml`.
3. New items arrive with the next update run (within 30 minutes), or press Refresh to update now.

**Variables:** `SELFOSS_USERNAME` (default `admin`), `SELFOSS_ADMIN_PASSWORD` (generated, at least 8 characters; change it in the variables and redeploy), `PORT` (8080). Any other [selfoss option](https://selfoss.aditu.de/docs/administration/options/) can be added as an upper-case `SELFOSS_OPTION_NAME` variable, for example `SELFOSS_ITEMS_LIFETIME=60` to keep items for 60 days, and `SELFOSS_UPDATE_INTERVAL_MINUTES` changes the update interval.

**Security:** upstream's advisory GHSA-2v57-rcgq-j44q (boolean options set to `false` were read as true, which could make an instance public) is still unfixed in a release. This template turns every boolean option into `0` or `1` before selfoss reads it, and refuses unknown values.

**Memory:** about 75 MB in use with 30 feeds and 600 items on a 0.5 GB / 1 vCPU service. Apache workers and PHP memory are sized from the service's limits, and if Apache stops the service exits with an error so Railway restarts it.

**Updates:** the service builds from our GitHub repository. When we publish a new selfoss version there, Railway shows an "update available" notice on your project, and you choose when to apply it. Read the repository's `CHANGELOG.md` first. Your data stays on the volume.

## Why Deploy selfoss on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying selfoss on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
<!-- End recommended section -->
