# Docker images

[![Scheduled build (Ubuntu)](https://github.com/catthehacker/docker_images/actions/workflows/build-ubuntu.yml/badge.svg?event=schedule)](https://github.com/catthehacker/docker_images/actions/workflows/build-ubuntu.yml)
[![On-demand build (Ubuntu)](https://github.com/catthehacker/docker_images/actions/workflows/build-ubuntu.yml/badge.svg?event=workflow_dispatch)](https://github.com/catthehacker/docker_images/actions/workflows/build-ubuntu.yml)
[![Linter](https://github.com/catthehacker/docker_images/actions/workflows/lint.yml/badge.svg)](https://github.com/catthehacker/docker_images/actions/workflows/lint.yml)

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

- [ChristopherHX/runner-image-blobs](https://github.com/ChristopherHX/runner-image-blobs) GitHub Actions Hosted runner image copy containing almost all possible tools (image is extremely big, 20GB compressed, ~60GB extracted)
  - A tar backup of the GitHub Hosted Runners are uploaded once a week via a custom docker image upload script in runner-image-blobs repository
  - Synced by cron job `.github/workflows/copy-full-image.yml` to the following tags
  - You can verify if the Image is still updated regulary by inspecting the dates in `docker buildx imagetools inspect catthehacker/ubuntu:full-latest --format "{{ json . }}"`
    - The friendly tag name version in the output can be looked up here https://github.com/actions/runner-images/releases to find out more about the sources
  - available tags are
    - `ghcr.io/catthehacker/ubuntu:full-latest` (aka `full-26.04`)
    - `ghcr.io/catthehacker/ubuntu:full-26.04`
    - `ghcr.io/catthehacker/ubuntu:full-24.04`
    - `ghcr.io/catthehacker/ubuntu:full-22.04`

- [`act`](./ansible/roles/act/tasks/main.yml) - image used in [github.com/nektos/act][nektos/act] as medium size image retaining compatibility with most actions while maintaining small size
  - `ghcr.io/catthehacker/ubuntu:act-22.04`
  - `ghcr.io/catthehacker/ubuntu:act-24.04`
  - `ghcr.io/catthehacker/ubuntu:act-26.04`
  - `ghcr.io/catthehacker/ubuntu:act-latest` (aka `act-26.04`)
- [`runner`](./ansible/roles/runner/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `runner` as user instead of `root`
  - `ghcr.io/catthehacker/ubuntu:runner-22.04`
  - `ghcr.io/catthehacker/ubuntu:runner-24.04`
  - `ghcr.io/catthehacker/ubuntu:runner-26.04`
  - `ghcr.io/catthehacker/ubuntu:runner-latest` (aka `runner-26.04`)
- [`js`](./ansible/roles/js/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `js` tools installed (`yarn`, `nvm`, `node` v20/v24, `pnpm`, `grunt`, etc.)
  - `ghcr.io/catthehacker/ubuntu:js-22.04`
  - `ghcr.io/catthehacker/ubuntu:js-24.04`
  - `ghcr.io/catthehacker/ubuntu:js-26.04`
  - `ghcr.io/catthehacker/ubuntu:js-latest` (aka `js-26.04`)
- [`rust`](./ansible/roles/rust/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `rust` tools installed (`rustfmt`, `clippy`, `cbindgen`, etc.)
  - `ghcr.io/catthehacker/ubuntu:rust-22.04`
  - `ghcr.io/catthehacker/ubuntu:rust-24.04`
  - `ghcr.io/catthehacker/ubuntu:rust-26.04`
  - `ghcr.io/catthehacker/ubuntu:rust-latest` (aka `rust-26.04`)
- [`pwsh`](./ansible/roles/pwsh/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `pwsh` tools and modules installed
  - `ghcr.io/catthehacker/ubuntu:pwsh-22.04`
  - `ghcr.io/catthehacker/ubuntu:pwsh-24.04`
  - `ghcr.io/catthehacker/ubuntu:pwsh-26.04`
  - `ghcr.io/catthehacker/ubuntu:pwsh-latest` (aka `pwsh-26.04`)
- [`go`](./ansible/roles/go/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `go` tools installed
  - `ghcr.io/catthehacker/ubuntu:go-22.04`
  - `ghcr.io/catthehacker/ubuntu:go-24.04`
  - `ghcr.io/catthehacker/ubuntu:go-26.04`
  - `ghcr.io/catthehacker/ubuntu:go-latest` (aka `go-26.04`)
- [`dotnet`](./ansible/roles/dotnet/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with `.NET` tools installed
  - `ghcr.io/catthehacker/ubuntu:dotnet-22.04`
  - `ghcr.io/catthehacker/ubuntu:dotnet-24.04`
  - `ghcr.io/catthehacker/ubuntu:dotnet-26.04`
  - `ghcr.io/catthehacker/ubuntu:dotnet-latest` (aka `dotnet-26.04`)
- [`java-tools`](./ansible/roles/java_tools/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with Java tools installed
  - `ghcr.io/catthehacker/ubuntu:java-tools-22.04`
  - `ghcr.io/catthehacker/ubuntu:java-tools-24.04`
  - `ghcr.io/catthehacker/ubuntu:java-tools-26.04`
  - `ghcr.io/catthehacker/ubuntu:java-tools-latest` (aka `java-tools-26.04`)
- [`gh`](./ansible/roles/gh/tasks/main.yml) - `ghcr.io/catthehacker/ubuntu:act-*` but with GitHub CLI tools installed
  - `ghcr.io/catthehacker/ubuntu:gh-22.04`
  - `ghcr.io/catthehacker/ubuntu:gh-24.04`
  - `ghcr.io/catthehacker/ubuntu:gh-26.04`
  - `ghcr.io/catthehacker/ubuntu:gh-latest` (aka `gh-26.04`)
- [`custom`](./ansible/group_vars/all.yml) (roles listed under `custom_roles`) - `ghcr.io/catthehacker/ubuntu:act-*` but with custom tools installed
  - `ghcr.io/catthehacker/ubuntu:custom-22.04`
  - `ghcr.io/catthehacker/ubuntu:custom-24.04`
  - `ghcr.io/catthehacker/ubuntu:custom-26.04`
  - `ghcr.io/catthehacker/ubuntu:custom-latest` (aka `custom-26.04`)

## [`ubuntu-20.04` has been deprecated and images for that environment will not be updated anymore](https://github.com/actions/runner-images/pull/11748)

## [`ubuntu-18.04` has been deprecated and images for that environment will not be updated anymore](https://github.com/actions/runner-images/issues/6002)

## Repository contains parts of [`actions/virtual-environments`][actions/virtual-environments] which is licenced under ["MIT License"](https://github.com/actions/virtual-environments/blob/main/LICENSE)

[nektos/act]: https://github.com/nektos/act
[actions/virtual-environments]: https://github.com/actions/virtual-environments
[catthehacker/virtual-environments-fork]: https://github.com/catthehacker/virtual-environments-fork/tree/master/images/linux
