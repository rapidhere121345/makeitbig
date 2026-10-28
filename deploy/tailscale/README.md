# Retired HTTP Release Page

The operator stopped the HTTP server. Downloads now live on
[GitHub Releases](https://github.com/rapidhere121345/makeitbig/releases).
Page templates, staging helpers, server commands, and host exposure examples
were removed. Project scripts must not restart the old service or configure
Tailscale/host networking.

`validate.sh` remains only as a compatibility check for older validation commands.
It checks that the old page/serving sources are absent and the GitHub publication
entry point exists. It neither serves files nor changes networking.

The old `release-online/` folder is retained intact under ignored
`build/archive/release-online-20261028/`. The new
workflow never reads, deletes, or prunes them. Historical acceptance records
still describe the old page as it existed at the time.
