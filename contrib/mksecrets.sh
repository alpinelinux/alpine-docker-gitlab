#!/bin/sh

set -eu

SECRETS_DIR=/srv/docker/compose/gitlab/secrets

mkdir -p "$SECRETS_DIR"

for sname in pg_admin pg_user root_pass; do
    [ -f "$SECRETS_DIR"/$sname.txt ] && continue
	echo "Generating $SECRETS_DIR/$sname.txt"
	head /dev/urandom | LC_CTYPE=C tr -dc A-Za-z0-9 | head -c 16 > \
		"$SECRETS_DIR"/$sname.txt
done
