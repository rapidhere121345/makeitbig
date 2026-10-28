# GitHub Release Sources

`notes.md` is the player-facing release copy; `config/release.conf` supplies the
repository, export locations, and local package root. Downloads are published on
[GitHub Releases](https://github.com/rapidhere121345/makeitbig/releases).

Generated packages live under ignored `build/releases/<tag>/` and contain Linux,
Windows, and Universal Mac archives, `build.json`, `RELEASE_NOTES.md`, and
`SHA256SUMS`. Packaging requires all three exports and refuses existing output
folders. There is no page generation, local serving, or automatic pruning.

See [the release workflow](../docs/RELEASE_WORKFLOW.md) for version tags,
validation, and publication. Old `release-online/` binary history is preserved under ignored `build/archive/`.
