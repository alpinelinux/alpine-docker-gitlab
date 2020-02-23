#!/bin/ash

set -euo pipefail

BRANCH=$1
OLDREV=$2
NEWREV=$3
MAIN=false

die() {
	local msg="$1"
	if [ "$GL_PROTOCOL" = "web" ]; then
		echo "GL-HOOK-ERR: $msg"
	else
		printf "\nHello %s\n" "$GL_USERNAME"
		printf "%s\n" "$msg"
		printf "If this is not correct please contact the Alpine Linux infra team\n\n"
	fi
	exit 1
}

if [ -z "${GL_USERNAME:-}" ]; then
	echo "Gitlab username not provided, aborting."
	exit 1
fi

# check if user is part of aports main acl
grep -q -x -F "$GL_USERNAME" /etc/gitlab/gitlab/aports-main.acl && exit 0

# a new branch is pushed and oldrev will be 0{40}
if [ "$OLDREV" = "0000000000000000000000000000000000000000" ]; then
	die "You are not allowed to push new branches"
fi

for rev in $(git rev-list "$OLDREV".."$NEWREV"); do
    git diff-tree --no-commit-id --name-only -r "$rev" | grep -q "^main/" && MAIN=true ; break
done

if [ "$MAIN" = true ]; then
	die "You are not allowed to push to the main repository"
fi

