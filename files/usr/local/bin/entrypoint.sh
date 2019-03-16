#!/bin/sh

# set -eu

INITCONF="
	gitlab.yml.example
	secrets.yml.example
	unicorn.rb.example
	initializers/rack_attack.rb.example
	resque.yml.example
	database.yml.postgresql
"

create_db() {
	local pg_user="$(cat /run/secrets/pg_user 2>/dev/null)"
	export PGPASSWORD=$(cat /run/secrets/pg_admin 2>/dev/null)
	psql -h postgres -U postgres -d template1 \
		-c "CREATE USER gitlab WITH CREATEDB ENCRYPTED PASSWORD '$pg_user';"
	psql -h postgres -U postgres -d template1 \
		-c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
	psql -h postgres -U postgres -d template1 \
		-c "CREATE DATABASE gitlabhq_production OWNER gitlab;"
}

create_conf() {
	echo "Setting up configurations..."
	for config in $INITCONF; do
		if [ ! -f "/etc/gitlab/${config%.*}" ]; then
			install -Dm644 /home/git/gitlab/config/$config \
				/etc/gitlab/${config%.*}
		else
			echo "Installing new config ${config%.*}.new"
			install -Dm644 /home/git/gitlab/config/$config \
				/etc/gitlab/${config%.*}.new
		fi
	done
	# gitlab shell
	if [ ! -f "/etc/gitlab/gitlab-shell/config.yml" ]; then
		install -Dm644 /home/git/gitlab-shell/config.yml.example \
			/etc/gitlab/gitlab-shell/config.yml
	fi
	# nginx
	if [ -f "/etc/gitlab/nginx/gitlab" ]; then
		install -Dm644 /home/git/gitlab/lib/support/nginx/gitlab \
			/etc/gitlab/nginx/gitlab.conf.new
	else
		install -Dm644 /home/git/gitlab/lib/support/nginx/gitlab \
			/etc/gitlab/nginx/gitlab.conf
	fi
}

prepare_conf() {
	echo "Preparing configuration"
	for config in $INITCONF; do
		ln -sf /etc/gitlab/${config%.*} \
			/home/git/gitlab/config/${config%.*}
	done
	ln -sf /etc/gitlab/nginx/gitlab.conf \
		/etc/nginx/conf.d/gitlab.conf
	rm -f /etc/nginx/conf.d/default.conf
}

postgres_conf() {
	local pg_user="$(cat /run/secrets/pg_user 2>/dev/null)"
	cat <<- EOF > /etc/gitlab/database.yml
	production:
	  adapter: postgresql
	  encoding: unicode
	  database: gitlabhq_production
	  pool: 10
	  username: gitlab
	  password: "$pg_user"
	  host: postgres
	EOF
}

redis_conf() {
	cat <<- EOF > /etc/gitlab/resque.yml
	production:
	  url: redis://redis:6379
	EOF
}

gitaly_config() {
	mkdir -p /etc/gitlab/gitaly
	cat <<- EOF > /etc/gitlab/gitaly/config.toml
	socket_path = "/home/git/gitlab/tmp/sockets/private/gitaly.socket"
	bin_dir = "/usr/local/bin"
	[[storage]]
	name = "default"
	path = "/home/git/repositories"
	[gitaly-ruby]
	dir = "/home/git/gitaly-ruby"
	[gitlab-shell]
	dir = "/home/git/gitlab-shell"
	EOF
}

setup_ssh() {
	echo "Creating ssh keys..."
	local keytype
	mkdir -p /etc/gitlab/ssh
	for keytype in ecdsa ed25519 rsa; do
		if [ ! -f "/etc/gitlab/ssh/ssh_host_${keytype}_key" ]; then
			ssh-keygen -q -N '' -t $keytype -f \
				/etc/gitlab/ssh/ssh_host_${keytype}_key
		fi
		ln -sf /etc/gitlab/ssh/ssh_host_${keytype}_key \
			/etc/ssh/ssh_host_${keytype}_key
		ln -sf /etc/gitlab/ssh/ssh_host_${keytype}_key.pub \
			/etc/ssh/ssh_host_${keytype}_key.pub
	done
}

setup_gitlab() {
	local root_pass="$(cat /run/secrets/root_pass 2>/dev/null)"
	echo "Setting up gitlab..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:setup RAILS_ENV=production force=yes \
		GITLAB_ROOT_PASSWORD="$root_pass"
}

update_perms() {
	echo "Updating permissions..."
	install -dm 700 -o git -g git \
		/home/git/gitlab/public/uploads \
		/home/git/gitlab/shared/pages \
		/home/git/gitlab/shared/artifacts \
		/home/git/gitlab/shared/lfs-objects	\
		/home/git/gitlab/shared/pages \
		/home/git/gitlab/shared/registry \
		/home/git/gitlab/log/s6
	chown -R git:git /etc/gitlab
	chmod -R u+rwX,go-w /home/git/gitlab/log
	chmod -R u+rwX /home/git/gitlab/tmp \
		/home/git/gitlab/builds
	chmod -R ug+rwX /home/git/gitlab/shared/pages
	chmod 1777 /tmp
}

verify() {
	echo "Verifying gitlab installation..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:env:info RAILS_ENV=production
}

setup() {
	create_db
	postgres_conf
	redis_conf
	gitaly_config
	create_conf
	setup_ssh
	setup_gitlab
	verify
	touch /etc/gitlab/.installed
}

upgrade() {
	echo "Hold on, no upgrade yet..."
}

backup() {
	echo "Hold on, no backups yet..."
}

start() {
	if [ -f "/etc/gitlab/.installed" ]; then
		echo "Configuration found"
	else
		setup
	fi
	update_perms
	prepare_conf
	echo "Starting Gitlab.."
	s6-svscan /etc/s6
}

case $1 in
	start) start ;;
	setup) setup ;;
	upgrade) upgrade ;;
	backup) backup ;;
	verify) verify ;;
	shell) /bin/sh ;;
	*) echo "No help yet" ;;
esac
