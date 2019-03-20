# Alpine Gitlab Docker

Alpine Linux based docker image and tools for Gitlab.

**NOTE**: ***This is a work in progress.***

## Why another Gitlab docker image?

 - Completely based on Alpine Linux (no static binaries)
 - Use separate docker images for services (where possible)
 - Optimized for size
 - Bundle all services with docker compose

## Setup

To get Gitlab up and running you need to first generate 3 secrets in the secrets
directory.

- PostgreSQL admin (pg_admin)
- PostgreSQL user (pg_user)
- Gitlab root user (root_pass)

Example of how to generate secrets

```bash
for sname in pg_admin pg_user root_pass; do
	head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16 > secrets/$sname.txt
done
```

After which you need to create and bring up the containers

```docker-compose up```

Watch the output on console for errors. It will take some time to generate the db
and update permissions. Ones its done without errors you can Ctrl+c to stop the
containers and start them again in the background.

## Access the application

Visit your Gitlab instance at http://dockerhost:8080

## Configuration

The default configuration is very limited. To make changes:

```bash 
cd /srv/docker/compose/gitlab/config
```

Modify a configuration file and restart the containers.

P.S. every restart the container will copy sample configs to the config
directory overwriting other sample configs if they already exist.
