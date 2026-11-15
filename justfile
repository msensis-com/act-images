# Builds the act images: buildah working containers provisioned by Ansible.
#
#   just deps                                   # install Ansible collections
#   just build act docker.io/library/buildpack-deps:24.04
#   just build js localhost/act-images/act:latest
#
# Environment knobs (all optional):
#   PLATFORMS          comma separated, default linux/amd64,linux/arm64
#   RUNNER             image USER (act: root, runner: runner); also the runner role's user name
#   NODE               Node.js majors for the act image, default "20 24"
#   BUILD_OWNER, BUILD_REPO, BUILD_REF, BUILD_TAG, BUILD_TAG_VERSION   OCI labels
#   CI tagging (see `tags`): SLUG, PART_TAG, LATEST_VERSION, PUSH_DEFAULT, PUSH_GHCR, PUSH_DOCKER_HUB

set shell := ["bash", "-euo", "pipefail", "-c"]

platforms := env_var_or_default("PLATFORMS", "linux/amd64,linux/arm64")

# List recipes
default:
    @just --list

# Install the Ansible collections needed by the build
deps:
    ansible-galaxy collection install -r ansible/requirements.yml

# Build TYPE on top of FROM for every platform into the local manifest list MANIFEST
build type from manifest=("localhost/act-images/" + type + ":latest"):
    #!/usr/bin/env bash
    set -euo pipefail
    # Rootless buildah needs a user namespace to mount containers (used by the Ansible connection plugin)
    if [[ "$(id -u)" != 0 ]]; then
        exec buildah unshare just --justfile "{{ justfile() }}" build "{{ type }}" "{{ from }}" "{{ manifest }}"
    fi
    cd "{{ justfile_directory() }}"
    export ANSIBLE_CONFIG="$PWD/ansible/ansible.cfg"

    created="$(date -u '+%Y-%m-%d %H:%M:%SZ')"
    repo="${BUILD_REPO:-}"
    ctr=""
    trap 'if [[ -n "$ctr" ]]; then buildah rm "$ctr" >/dev/null 2>&1 || true; fi' EXIT

    buildah manifest rm "{{ manifest }}" >/dev/null 2>&1 || true
    buildah manifest create "{{ manifest }}"

    IFS=',' read -ra plats <<< "{{ platforms }}"
    for platform in "${plats[@]}"; do
        arch="${platform#*/}"
        arch="${arch%%/*}"
        ctr="act-images-{{ type }}-${arch}-$$"
        echo "==> {{ type }} ($platform) from {{ from }}"

        buildah from --name "$ctr" --platform "$platform" --format docker \
            --ulimit nofile=4096:4096 "{{ from }}"

        ansible_args=(-e "image_type={{ type }}" -e "node_versions_str=${NODE:-}")
        if [[ -n "${RUNNER:-}" && "${RUNNER}" != root ]]; then
            ansible_args+=(-e "runner_user=$RUNNER")
        fi
        ansible-playbook ansible/site.yml -i "$ctr," -c containers.podman.buildah "${ansible_args[@]}"
        buildah run "$ctr" -- rm -rf /root/.ansible

        # /etc/environment is the source of truth for the image ENV (act reads ENV, not the file)
        config_args=(--env DEBIAN_FRONTEND=noninteractive)
        while IFS= read -r line; do
            if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                config_args+=(--env "$line")
            fi
        done < <(buildah run "$ctr" -- cat /etc/environment)
        if [[ -n "${RUNNER:-}" ]]; then
            config_args+=(--user "$RUNNER")
        fi

        buildah config "${config_args[@]}" \
            --workingdir /tmp \
            --label "org.opencontainers.image.created=$created" \
            --label "org.opencontainers.image.vendor=${BUILD_OWNER:-}" \
            --label "org.opencontainers.image.authors=https://github.com/${BUILD_OWNER:-}" \
            --label "org.opencontainers.image.url=https://github.com/${repo}/tree/${BUILD_REF:-}" \
            --label "org.opencontainers.image.source=https://github.com/${repo}" \
            --label "org.opencontainers.image.documentation=https://github.com/${repo}" \
            --label "org.opencontainers.image.version=${BUILD_TAG_VERSION:-}" \
            --label "org.opencontainers.image.title=${BUILD_TAG:-{{ type }}}-${arch}" \
            --label "org.opencontainers.image.description=Special image built for using with https://github.com/nektos/act" \
            --label "org.opencontainers.image.revision=${BUILD_REF:-}" \
            "$ctr"

        img="localhost/act-images-build/{{ type }}-${arch}:$$"
        buildah commit --format docker --rm "$ctr" "$img"
        ctr=""
        buildah manifest add "{{ manifest }}" "$img"
    done
    echo "==> built {{ manifest }}"

# Push local manifest list MANIFEST (all platforms) to each TAG, retrying 3 times
push manifest +tags:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{ tags }}; do
        for attempt in 1 2 3; do
            if buildah manifest push --all "{{ manifest }}" "docker://$t"; then
                continue 2
            fi
            echo "Error pushing $t, retrying... ($attempt/3)" >&2
            sleep 2
        done
        echo "Failed to push $t after 3 attempts." >&2
        exit 1
    done

# Print the registry tags for TYPE on Ubuntu VERSION (driven by CI environment variables)
tags type version:
    #!/usr/bin/env bash
    set -euo pipefail
    slug="$(echo "${SLUG:?SLUG must be set, e.g. owner/ubuntu}" | tr '[:upper:]' '[:lower:]')"
    part="${PART_TAG:?PART_TAG must be set, e.g. dev or 20260101}"
    latest=""
    if [[ "{{ version }}" == "${LATEST_VERSION:-}" ]]; then latest=1; fi

    names=("{{ type }}-{{ version }}-$part")
    if [[ -n "$latest" ]]; then names+=("{{ type }}-latest-$part"); fi
    if [[ -n "${PUSH_DEFAULT:-}" ]]; then
        names+=("{{ type }}-{{ version }}")
        if [[ -n "$latest" ]]; then names+=("{{ type }}-latest"); fi
    fi

    for n in "${names[@]}"; do
        if [[ -n "${PUSH_GHCR:-}" ]]; then echo "ghcr.io/$slug:$n"; fi
        if [[ -n "${PUSH_DOCKER_HUB:-}" ]]; then echo "docker.io/$slug:$n"; fi
    done

# CI entrypoint: build TYPE for Ubuntu VERSION on top of FROM, then push it to every tag from `tags`
ci type version from:
    #!/usr/bin/env bash
    set -euo pipefail
    export BUILD_TAG="${BUILD_TAG:-{{ type }}-{{ version }}}"
    export BUILD_TAG_VERSION="${BUILD_TAG_VERSION:-${PART_TAG:-}}"
    tags_out="$(just --justfile "{{ justfile() }}" tags "{{ type }}" "{{ version }}")"
    mapfile -t tags <<< "$tags_out"
    manifest="localhost/act-images/{{ type }}:{{ version }}"
    just --justfile "{{ justfile() }}" build "{{ type }}" "{{ from }}" "$manifest"
    if [[ -n "$tags_out" ]]; then
        printf 'pushing %s\n' "${tags[@]}"
        just --justfile "{{ justfile() }}" push "$manifest" "${tags[@]}"
    else
        echo "No registry enabled, not pushing"
    fi

# Lint the Ansible code
lint:
    cd ansible && ansible-lint

# Run nektos/act's test suite against IMAGE (clones act into ACT_SRC, default .act-src)
test image:
    #!/usr/bin/env bash
    set -euo pipefail
    src="${ACT_SRC:-{{ justfile_directory() }}/.act-src}"
    if [[ ! -d "$src" ]]; then git clone --depth 1 https://github.com/nektos/act "$src"; fi
    cd "$src"
    ACT_TEST_IMAGE="{{ image }}" go test ./...
