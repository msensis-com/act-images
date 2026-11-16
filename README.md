# act images

[![Scheduled build (Ubuntu)](https://github.com/msensis-com/act-images/actions/workflows/build-ubuntu.yml/badge.svg?event=schedule)](https://github.com/msensis-com/act-images/actions/workflows/build-ubuntu.yml)
[![On-demand build (Ubuntu)](https://github.com/msensis-com/act-images/actions/workflows/build-ubuntu.yml/badge.svg?event=workflow_dispatch)](https://github.com/msensis-com/act-images/actions/workflows/build-ubuntu.yml)
[![Linter](https://github.com/msensis-com/act-images/actions/workflows/lint.yml/badge.svg)](https://github.com/msensis-com/act-images/actions/workflows/lint.yml)

Ubuntu images for running GitHub Actions workflows locally with [nektos/act], published to `ghcr.io/msensis-com/ubuntu`.

Originally forked from [catthehacker/docker_images](https://github.com/catthehacker/docker_images) and maintained independently since; the build was rewritten from Dockerfile + shell scripts to Ansible.

## When updates will be applied to images

- A package that will be required for action(s) to work properly might be added/removed/changed
- Any maintenance that will be required due to:
  - GitHub Container Registry
  - GitHub Actions
  - Act
- Performance and/or disk space improvements

## How images are built

Images are provisioned with [Ansible](https://docs.ansible.com/) through [buildah](https://buildah.io/) working containers, driven by a [`justfile`](./justfile). There is no Dockerfile:

```text
buildah from --platform <p> <FROM>                    # e.g. buildpack-deps:24.04, or the act image for flavours
  -> ansible-playbook -c containers.podman.buildah    # ansible/site.yml applies the roles for the image type
  -> buildah config --env <each line of /etc/environment> --label ...
  -> buildah commit, then add to a multi-arch manifest list (linux/amd64 + linux/arm64)
```

In CI ([`build-ubuntu.yml`](./.github/workflows/build-ubuntu.yml)) every architecture is built natively (`ubuntu-26.04` / `ubuntu-26.04-arm`) and pushed to a private staging package; publish jobs then combine amd64 + arm64 into the tags listed below. Scheduled builds run weekly and also push dated tags (e.g. `act-24.04-20261115`); pushes to `master` publish `*-dev` tags.

- [`ansible/group_vars/all.yml`](./ansible/group_vars/all.yml) maps each image type to its roles (`image_roles`)
- [`ansible/roles/`](./ansible/roles) contains one role per tool set (`act`, `runner`, `go`, `js`, `pwsh`, `rust`, `dotnet`, `java_tools`, `gh`, ...)
- `/etc/environment` inside the image is the source of truth for the environment, and is copied into the image `ENV` (which is what [nektos/act] uses)

### Building locally

Requirements: `buildah`, `ansible-core`, `just`, and `qemu-user-static` (binfmt) for non-native platforms.

```sh
just deps                                                     # install the Ansible collections
PLATFORMS=linux/amd64 RUNNER=root just build act docker.io/library/buildpack-deps:24.04 localhost/act-images/act:24.04
PLATFORMS=linux/amd64 RUNNER=runner just build runner localhost/act-images/act:24.04
PLATFORMS=linux/amd64 just build js localhost/act-images/act:24.04
just test localhost/act-images/act:24.04                      # run nektos/act's test suite against an image
just lint
```

## Images available

- `full` - a snapshot of GitHub's own hosted runner (`ubuntu-<version>` / `ubuntu-<version>-arm`) containing almost all possible tools (image is extremely big, ~20GB compressed, ~60GB extracted)
  - Taken weekly by [`.github/workflows/snapshot-full-image.yml`](./.github/workflows/snapshot-full-image.yml): each runner tars its own root filesystem in chunks and streams them straight into GHCR as image layers ([`.github/scripts/ghcr-stream.mjs`](./.github/scripts/ghcr-stream.mjs)), because a runner does not have enough disk to build or pull an image this size. Method from [ChristopherHX/runner-image-blobs](https://github.com/ChristopherHX/runner-image-blobs)
  - The runner image version is in the `org.opencontainers.image.version` label (`docker buildx imagetools inspect ghcr.io/msensis-com/ubuntu:full-latest --format "{{ json . }}"`); look it up in https://github.com/actions/runner-images/releases
  - available tags are
    - `ghcr.io/msensis-com/ubuntu:full-latest` (aka `full-26.04`)
    - `ghcr.io/msensis-com/ubuntu:full-26.04`
    - `ghcr.io/msensis-com/ubuntu:full-24.04`
    - `ghcr.io/msensis-com/ubuntu:full-22.04`
    - single-architecture variants: `full-<version>-amd64`, `full-<version>-arm64`

- [`act`](./ansible/roles/act/tasks/main.yml) - image used in [github.com/nektos/act][nektos/act] as medium size image retaining compatibility with most actions while maintaining small size
  - `ghcr.io/msensis-com/ubuntu:act-22.04`
  - `ghcr.io/msensis-com/ubuntu:act-24.04`
  - `ghcr.io/msensis-com/ubuntu:act-26.04`
  - `ghcr.io/msensis-com/ubuntu:act-latest` (aka `act-26.04`)
- [`runner`](./ansible/roles/runner/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `runner` as user instead of `root`
  - `ghcr.io/msensis-com/ubuntu:runner-22.04`
  - `ghcr.io/msensis-com/ubuntu:runner-24.04`
  - `ghcr.io/msensis-com/ubuntu:runner-26.04`
  - `ghcr.io/msensis-com/ubuntu:runner-latest` (aka `runner-26.04`)
- [`js`](./ansible/roles/js/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `js` tools installed (`yarn`, `nvm`, `node` v20/v24, `pnpm`, `grunt`, etc.)
  - `ghcr.io/msensis-com/ubuntu:js-22.04`
  - `ghcr.io/msensis-com/ubuntu:js-24.04`
  - `ghcr.io/msensis-com/ubuntu:js-26.04`
  - `ghcr.io/msensis-com/ubuntu:js-latest` (aka `js-26.04`)
- [`rust`](./ansible/roles/rust/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `rust` tools installed (`rustfmt`, `clippy`, `cbindgen`, etc.)
  - `ghcr.io/msensis-com/ubuntu:rust-22.04`
  - `ghcr.io/msensis-com/ubuntu:rust-24.04`
  - `ghcr.io/msensis-com/ubuntu:rust-26.04`
  - `ghcr.io/msensis-com/ubuntu:rust-latest` (aka `rust-26.04`)
- [`pwsh`](./ansible/roles/pwsh/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `pwsh` tools and modules installed
  - `ghcr.io/msensis-com/ubuntu:pwsh-22.04`
  - `ghcr.io/msensis-com/ubuntu:pwsh-24.04`
  - `ghcr.io/msensis-com/ubuntu:pwsh-26.04`
  - `ghcr.io/msensis-com/ubuntu:pwsh-latest` (aka `pwsh-26.04`)
- [`go`](./ansible/roles/go/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `go` tools installed
  - `ghcr.io/msensis-com/ubuntu:go-22.04`
  - `ghcr.io/msensis-com/ubuntu:go-24.04`
  - `ghcr.io/msensis-com/ubuntu:go-26.04`
  - `ghcr.io/msensis-com/ubuntu:go-latest` (aka `go-26.04`)
- [`dotnet`](./ansible/roles/dotnet/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with `.NET` tools installed
  - `ghcr.io/msensis-com/ubuntu:dotnet-22.04`
  - `ghcr.io/msensis-com/ubuntu:dotnet-24.04`
  - `ghcr.io/msensis-com/ubuntu:dotnet-26.04`
  - `ghcr.io/msensis-com/ubuntu:dotnet-latest` (aka `dotnet-26.04`)
- [`java-tools`](./ansible/roles/java_tools/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with Java tools installed
  - `ghcr.io/msensis-com/ubuntu:java-tools-22.04`
  - `ghcr.io/msensis-com/ubuntu:java-tools-24.04`
  - `ghcr.io/msensis-com/ubuntu:java-tools-26.04`
  - `ghcr.io/msensis-com/ubuntu:java-tools-latest` (aka `java-tools-26.04`)
- [`gh`](./ansible/roles/gh/tasks/main.yml) - `ghcr.io/msensis-com/ubuntu:act-*` but with GitHub CLI tools installed
  - `ghcr.io/msensis-com/ubuntu:gh-22.04`
  - `ghcr.io/msensis-com/ubuntu:gh-24.04`
  - `ghcr.io/msensis-com/ubuntu:gh-26.04`
  - `ghcr.io/msensis-com/ubuntu:gh-latest` (aka `gh-26.04`)
- [`custom`](./ansible/group_vars/all.yml) (roles listed under `custom_roles`) - `ghcr.io/msensis-com/ubuntu:act-*` but with custom tools installed
  - `ghcr.io/msensis-com/ubuntu:custom-22.04`
  - `ghcr.io/msensis-com/ubuntu:custom-24.04`
  - `ghcr.io/msensis-com/ubuntu:custom-26.04`
  - `ghcr.io/msensis-com/ubuntu:custom-latest` (aka `custom-26.04`)

## [`ubuntu-20.04` has been deprecated and images for that environment will not be updated anymore](https://github.com/actions/runner-images/pull/11748)

## [`ubuntu-18.04` has been deprecated and images for that environment will not be updated anymore](https://github.com/actions/runner-images/issues/6002)

## Repository contains parts of [`actions/virtual-environments`][actions/virtual-environments] which is licenced under ["MIT License"](https://github.com/actions/virtual-environments/blob/main/LICENSE)

[nektos/act]: https://github.com/nektos/act
[actions/virtual-environments]: https://github.com/actions/virtual-environments
