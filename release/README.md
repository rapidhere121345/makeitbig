# GitHub Release Sources

`notes.md` is the player-facing release copy and `config/release.conf` supplies
the repository, export locations, and local package root. Packaging, verification,
publication, and the retired HTTP page's archive are described in the
[release workflow](../docs/RELEASE_WORKFLOW.md); generated packages go to ignored
`build/releases/<tag>/` and are never committed.
