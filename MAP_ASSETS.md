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

## Automated weekly updates

On mini, `pixi run map-auto-update` is the single entry point. It selects
the newest OpenRS2 cache with `game=oldschool`, `environment=live`, and a
valid build (latest timestamp, then more published keys, then higher id;
null timestamps cannot beat a dated cache). OpenRS2 stopped attaching
XTEAs after March 2026, so `valid_keys == 0` is not a reason to skip a
later cache; keys are borrowed from the newest cache that still publishes
them and recorded as `openrs2_xtea_cache_id`. The map dumper's object
loader consumes the later object-definition opcodes (including 97/98)
so a post-March live cache can actually render. Later live caches also
drop MAPS name hashes (`named=false`); the dumper then treats each
archive id as a region id (file 0 terrain, file 1 locations). The job regenerates the
four surface floors (and underground assets when the locked rebuild can
run) when that cache id is newer than the pin, and compares the generated
files to the pinned bytes. A cache bump that does not change those bytes
produces no release and no PR.

When the map did change, the job publishes a **new** versioned
`osrswiki/osrswiki-tooling` release (`map-assets-v1-<12-hex>` from the
content fingerprint) and opens a pin-bump PR on `osrswiki-fleet`. It never
clobbers or deletes a tag that an existing pin, shipped build, or F-Droid
metadata still downloads. `--dry-run` does the same work except upload and
PR. The pin's `provenance.openrs2_cache_id` is what later freshness checks
compare against. MBTiles comparison uses tile PNG payloads and metadata,
not the SQLite wrapper bytes, so a rebuild of the same map does not
publish.

A LaunchAgent (`com.omiyawaki.osrswiki.map-auto-update`) runs that command
every Wednesday at 14:00 local time, a few hours after the usual OSRS
update. Install it with
`./scripts/shared/install-map-auto-update-launchagent.sh`. Logs go to
`~/Library/Logs/osrswiki/map-auto-update/`. Failures exit nonzero and open
or comment on a GitHub issue; there is no email or chat send. GitHub
Actions is not used: generation needs mini's host-local cache, Java, and
Pixi, and `gh auth` on mini already covers the tooling org and the fleet
repo without new secrets.

New maps ride the next iOS / Play / F-Droid app release. In-app runtime
download is out of scope. F-Droid's `fdroiddata` zip pin is still updated
by hand at FOSS release time.

## Publishing the zip

`map_floors.zip` is created and uploaded only by Fleet map-release
automation (`map-auto-update.sh` or `publish-map-release-bundle.sh`). Do
not `gh release upload` it by hand, and do not hand-edit fdroiddata curl
lists.

From the fleet checkout, after the four mbtiles exist and match the
per-file pins:

```bash
./scripts/shared/publish-map-release-bundle.sh --create-release
```

`--create-release` makes a new tag when the manifest names one that does
not exist yet. `--clobber` remains available for the rare case of
repairing the *same* tag and must not be used by auto-update.

Or from `tools/`:

```bash
pixi run publish-map-bundle --create-release
pixi run map-auto-update --dry-run
```

That publish script builds a deterministic zip (stable member order, ZIP
epoch timestamps, Unix 0644 attrs, deflate level 9), writes
`bundle.sha256` / `bundle.bytes` into
`shared/manifests/osrs-map-assets-v1.json`, and uploads the zip to the
`osrswiki/osrswiki-tooling` GitHub Release named by the manifest. Matching
remote size skips the upload. `--dry-run` builds and pins locally without
calling `gh`.

`deploy-android.sh` / `publish-public-trees.sh` project the fetch script and
manifest into the public android tree so later FOSS deploys keep shipping
this one-zip recipe. They do not upload the zip.

Generated source PNGs and other map-building intermediates remain host-local
and are never published as Git history.
