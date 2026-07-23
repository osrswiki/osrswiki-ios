#!/bin/bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage:
  fetch-map-release-assets.sh validate-manifest <manifest.json>
  fetch-map-release-assets.sh verify <manifest.json> <asset-directory>
  fetch-map-release-assets.sh materialize <manifest.json> <asset-directory>
  fetch-map-release-assets.sh release-tag <manifest.json>

materialize uses OSRS_MAP_ASSET_SOURCE_DIR when set; otherwise it downloads the
immutable assets from the GitHub release named by the manifest.
EOF
    exit 2
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command is unavailable: $1" >&2
        exit 2
    fi
}

file_size() {
    if stat -f '%z' "$1" >/dev/null 2>&1; then
        stat -f '%z' "$1"
    else
        stat -c '%s' "$1"
    fi
}

file_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        echo "ERROR: shasum or sha256sum is required" >&2
        exit 2
    fi
}

validate_manifest() {
    local manifest="$1"
    [[ -f "$manifest" ]] || {
        echo "ERROR: map asset manifest not found: $manifest" >&2
        return 1
    }
    require_command jq

    jq -e '
        .schema_version == 1
        and (.asset_set_id | type == "string" and test("^osrs-surface-maps-[0-9a-f]{12}$"))
        and (.repository == "osrswiki/osrswiki-tooling")
        and (.release_tag | type == "string" and test("^map-assets-v1-[0-9a-f]{12}$"))
        and (
            (.asset_set_id | sub("^osrs-surface-maps-"; ""))
            == (.release_tag | sub("^map-assets-v1-"; ""))
        )
        and (.assets | type == "array" and length == 4)
        and ([.assets[].name] | sort == [
            "map_floor_0.mbtiles",
            "map_floor_1.mbtiles",
            "map_floor_2.mbtiles",
            "map_floor_3.mbtiles"
        ])
        and ([.assets[].name] | unique | length == 4)
        and (all(.assets[];
            (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
            and (.bytes | type == "number" and . > 0 and floor == .)
        ))
        and (.provenance.artifact_class == "immutable-reproducible-release")
        and (.provenance.generated_intermediates == "host-local-only")
    ' "$manifest" >/dev/null
}

verify_assets() {
    local manifest="$1"
    local asset_dir="$2"
    local name expected_sha expected_bytes asset_file actual_sha actual_bytes

    validate_manifest "$manifest"
    [[ -d "$asset_dir" ]] || {
        echo "ERROR: map asset directory not found: $asset_dir" >&2
        return 1
    }

    while IFS=$'\t' read -r name expected_sha expected_bytes; do
        asset_file="$asset_dir/$name"
        if [[ ! -f "$asset_file" || -L "$asset_file" ]]; then
            echo "ERROR: required regular map asset is missing: $asset_file" >&2
            return 1
        fi
        actual_bytes="$(file_size "$asset_file")"
        actual_sha="$(file_sha256 "$asset_file")"
        if [[ "$actual_bytes" != "$expected_bytes" ]]; then
            echo "ERROR: map asset size mismatch for $name: expected $expected_bytes, got $actual_bytes" >&2
            return 1
        fi
        if [[ "$actual_sha" != "$expected_sha" ]]; then
            echo "ERROR: map asset checksum mismatch for $name" >&2
            return 1
        fi
    done < <(jq -r '.assets[] | [.name, .sha256, (.bytes | tostring)] | @tsv' "$manifest")
}

copy_verified_assets() {
    local manifest="$1"
    local source_dir="$2"
    local destination_dir="$3"
    local name temporary_file

    verify_assets "$manifest" "$source_dir"
    mkdir -p "$destination_dir"
    while IFS= read -r name; do
        temporary_file="$destination_dir/.${name}.fleet-sync-tmp.$$"
        cp "$source_dir/$name" "$temporary_file"
        chmod 0644 "$temporary_file"
        mv -f "$temporary_file" "$destination_dir/$name"
    done < <(jq -r '.assets[].name' "$manifest")
    verify_assets "$manifest" "$destination_dir"
}

download_assets() {
    local manifest="$1"
    local destination_dir="$2"
    local repository release_tag name download_url

    require_command curl
    repository="$(jq -r '.repository' "$manifest")"
    release_tag="$(jq -r '.release_tag' "$manifest")"
    mkdir -p "$destination_dir"

    while IFS= read -r name; do
        download_url="https://github.com/$repository/releases/download/$release_tag/$name"
        curl --fail --location --retry 3 --retry-all-errors \
            --output "$destination_dir/$name" "$download_url"
    done < <(jq -r '.assets[].name' "$manifest")
    verify_assets "$manifest" "$destination_dir"
}

materialize_assets() {
    local manifest="$1"
    local destination_dir="$2"
    local temporary_dir

    validate_manifest "$manifest"
    if [[ -n "${OSRS_MAP_ASSET_SOURCE_DIR:-}" ]]; then
        copy_verified_assets "$manifest" "$OSRS_MAP_ASSET_SOURCE_DIR" "$destination_dir"
        return
    fi

    temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/osrs-map-release.XXXXXX")"
    download_assets "$manifest" "$temporary_dir"
    copy_verified_assets "$manifest" "$temporary_dir" "$destination_dir"
    rm -rf -- "$temporary_dir"
}

[[ $# -ge 2 ]] || usage
command_name="$1"
manifest_path="$2"

case "$command_name" in
    validate-manifest)
        [[ $# -eq 2 ]] || usage
        validate_manifest "$manifest_path"
        ;;
    verify)
        [[ $# -eq 3 ]] || usage
        verify_assets "$manifest_path" "$3"
        ;;
    materialize)
        [[ $# -eq 3 ]] || usage
        materialize_assets "$manifest_path" "$3"
        ;;
    release-tag)
        [[ $# -eq 2 ]] || usage
        validate_manifest "$manifest_path"
        jq -r '.release_tag' "$manifest_path"
        ;;
    *)
        usage
        ;;
esac
