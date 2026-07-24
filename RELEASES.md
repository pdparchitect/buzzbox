# Releasing Buzzbox

Buzzbox releases are driven by the `VERSION` file.

## Release process

1. Update `VERSION` with a semantic version without a `v` prefix.
2. Move the relevant entries from `Unreleased` into a matching version section
   in `CHANGELOG.md`.
3. Merge the release change into `main`.
4. CI builds and smoke-tests the Buzzbox image.
5. After CI succeeds, the tag workflow creates an annotated `v*` tag at the
   exact tested commit.
6. The release workflow publishes the image to
   `ghcr.io/pdparchitect/buzzbox`, creates its immutable version tags, and
   creates a matching GitHub Release.

Existing tags and releases are never replaced.

## Image tags

Stable releases publish the following tags:

- `vX.Y.Z`
- `X.Y.Z`
- `X.Y`
- `latest`

Prereleases publish the versioned tags but do not move `latest`.

The image is OCI-compatible and can be run by Docker, Podman, containerd with
nerdctl, and other OCI runtimes. It currently targets `linux/amd64` because the
upstream Buzz desktop package is only available for that architecture.

## Package visibility

The workflow can create and update the GitHub Container Registry package using
the repository's `GITHUB_TOKEN`. After the first publication, a repository or
organization owner must make the package public in GitHub package settings so
anyone can pull it without authentication.
