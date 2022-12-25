#!/bin/sh
# shellcheck disable=SC3060

# shellcheck disable=SC3040
set -eu -o pipefail

. "$(dirname "$0")"/../VERSIONS

if [ -z "${GITLAB_VERSION:-}" ]; then
    echo "Please provide GITLAB_VERSION environment variable" >&2
    exit 1
fi

base_url="https://gitlab.com/gitlab-org/gitlab/-/raw/v$GITLAB_VERSION-ee"

printf "GITLAB_VERSION=%s\n" "$GITLAB_VERSION"
printf "GITLAB_MAJOR_VERSION=%s\n" "${GITLAB_VERSION%.*}"
printf "GITLAB_WORKHORSE_VERSION=%s\n" "$GITLAB_VERSION"

for F in GITALY_SERVER_VERSION GITLAB_SHELL_VERSION ; do
    url="$base_url/$F"
    version=$(curl -Ss --fail "$url")
    printf "%s=%s\n" "$F" "$version"
done
