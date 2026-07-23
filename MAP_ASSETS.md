# Map release assets

The four `map_floor_*.mbtiles` files required by release builds are immutable
GitHub Release assets, not Git source.

The pinned release and each file's SHA-256 and byte size are recorded in
`map-assets-manifest.json`. Materialize and verify the files before a release
build:

```bash
./scripts/fetch-map-assets.sh materialize \
  map-assets-manifest.json \
  app/src/main/assets
```

For the iOS repository, use `osrswiki` as the destination directory.

The script downloads only the release named by the manifest and rejects a
missing file, unexpected manifest entry, size mismatch, or checksum mismatch.
Generated source PNGs and other map-building intermediates remain host-local
and are never published as Git history.
