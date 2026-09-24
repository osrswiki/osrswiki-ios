# Map release assets

The four `map_floor_*.mbtiles` files required by release builds are immutable
GitHub Release assets, not Git source. FOSS and F-Droid consume them as **one**
`map_floors.zip` from that same tooling release. Per-file SHA-256 and byte
sizes remain the source of truth after extract.

The pinned release, the zip digest, and each member's SHA-256 and byte size
are recorded in `map-assets-manifest.json`. Materialize and verify the files
before a release build:

```bash
./scripts/fetch-map-assets.sh materialize \
  map-assets-manifest.json \
  app/src/main/assets
```

For the iOS repository, use `osrswiki` as the destination directory.

The default download path is a single zip URL. The script verifies the zip
digest, extracts the four floors, then verifies each `.mbtiles` pin. Set
`OSRS_MAP_ASSET_SOURCE_DIR` to use already-verified local copies instead of
HTTP. The script rejects a missing file, unexpected manifest entry, size
mismatch, or checksum mismatch. Materialize needs `curl`, `jq`, and
`python3`; the public tree ships `scripts/osrs_map_release_bundle.py` beside
`scripts/fetch-map-assets.sh`.

Do not curl the four `map_floor_*.mbtiles` files separately in F-Droid
prebuild. Prefer the materialize command above.

## Publishing the zip

`map_floors.zip` is created and uploaded only by Fleet map-release
automation. Do not `gh release upload` it by hand, and do not hand-edit
fdroiddata curl lists.

From the fleet checkout, after the four mbtiles exist and match the
per-file pins:

```bash
./scripts/shared/publish-map-release-bundle.sh --clobber
```

Or from `tools/`:

```bash
pixi run publish-map-bundle --clobber
```

That script builds a deterministic zip (stable member order, ZIP epoch
timestamps, Unix 0644 attrs, deflate level 9), writes `bundle.sha256` /
`bundle.bytes` into `shared/manifests/osrs-map-assets-v1.json`, and uploads
the zip to the `osrswiki/osrswiki-tooling` GitHub Release named by the
manifest. It is idempotent: matching remote size skips the upload; pass
`--clobber` to replace a differing asset or refresh pins. `--dry-run`
builds and pins locally without calling `gh`.

`deploy-android.sh` / `publish-public-trees.sh` project the fetch script and
manifest into the public android tree so later FOSS deploys keep shipping
this one-zip recipe. They do not upload the zip.

Generated source PNGs and other map-building intermediates remain host-local
and are never published as Git history.
