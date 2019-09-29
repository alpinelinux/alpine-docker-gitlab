#!/bin/sh

set -eu

# base config files found in gitlab/config dir
BASECONF="
	gitlab/gitlab.yml.example
	gitlab/secrets.yml.example
	gitlab/unicorn.rb.example
	gitlab/puma.rb.example
	gitlab/initializers/rack_attack.rb.example
	gitaly/config.toml.example
	gitlab-shell/config.yml.example
"

create_db() {
	local pg_user="$(cat /run/secrets/pg_user 2>/dev/null)"
	export PGPASSWORD=$(cat /run/secrets/pg_admin 2>/dev/null)
	echo "Connecting to postgres.."
	while ! pg_isready -qh postgres; do sleep 1; done
	echo "Connection succesful, creating database.."
	if psql -lqt -h postgres -U postgres -d template1 | cut -d \| -f 1 | grep -qw gitlabhq_production; then
		echo "Database exists already."
	else
		psql -h postgres -U postgres -d template1 \
			-c "CREATE USER gitlab WITH CREATEDB ENCRYPTED PASSWORD '$pg_user';"
		psql -h postgres -U postgres -d template1 \
			-c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
		psql -h postgres -U postgres -d template1 \
			-c "CREATE DATABASE gitlabhq_production OWNER gitlab;"
	fi
}

# install config if not yet exist
install_conf() {
	local config
	for config in $BASECONF; do
		if [ ! -f "/etc/gitlab/${config%.*}" ]; then
			echo "Installing missing config: ${config%.*}"
			local dest=${config%.*}
			case $config in gitlab/*) config=${config#*/};; esac
			install -Dm644 /home/git/gitlab/config/$config \
				/etc/gitlab/$dest
		fi
	done
	if [ ! -f "/etc/gitlab/logrotate/gitlab" ]; then
		install -Dm644 /home/git/gitlab/lib/support/logrotate/gitlab \
			/etc/gitlab/logrotate/gitlab
	fi
	if [ ! -f "/etc/gitlab/nginx/conf.d/default.conf" ]; then
		install -Dm644 /home/git/gitlab/lib/support/nginx/gitlab \
			/etc/gitlab/nginx/conf.d/default.conf
	fi
}

link_config() {
	local src=$1 dst=$2 file=
	for file in $(find "$src" -type f -not -name ".*"); do
		mkdir -p $(dirname "$dst/${file#*$src/}")
		ln -sf "$file" "$dst/${file#*$src/}"
	done
}

enable_services() {
	local web=unicorn
	case ${USE_PUMA:-false} in
		[Yy]|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|1) web=puma;;
	esac
	rm -rf /run/s6 && mkdir -p /run/s6
	for srv in gitaly nginx sidekiq sshd workhorse; do
		ln -sf /etc/s6/$srv /run/s6/$srv
	done
	ln -sf /etc/s6/$web /run/s6/web
}

prepare_conf() {
	echo "Preparing configuration.."
	link_config "/etc/gitlab/gitlab" "/home/git/gitlab/config"
	link_config "/etc/gitlab/ssh" "/etc/ssh"
	link_config "/etc/gitlab/nginx" "/etc/nginx"
	link_config "/etc/gitlab/gitlab-shell" "/home/git/gitlab-shell"
	link_config "/etc/gitlab/logrotate/" "/etc/logrotate.d"
}

rebuild_conf() {
	if [ ! -f "/home/git/.ssh/authorized_keys" ]; then
		echo "Rebuild gitlab-shell configuration files.."
		cd /home/git/gitlab
		force=yes su-exec git \
			bundle exec rake gitlab:shell:setup RAILS_ENV=production
	fi
}

postgres_conf() {
	local pg_user="$(cat /run/secrets/pg_user 2>/dev/null)"
	cat <<- EOF > /etc/gitlab/gitlab/database.yml
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
	cat <<- EOF > /etc/gitlab/gitlab/resque.yml
	production:
	  url: redis://redis:6379
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
	done
}

setup_gitlab() {
	local root_pass="$(cat /run/secrets/root_pass 2>/dev/null)"
	echo "Setting up gitlab..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:setup RAILS_ENV=production force=yes \
		GITLAB_ROOT_PASSWORD="$root_pass"
}

prepare_dirs() {
	echo "Updating directories..."
	# create missing directories
	install -dm 700 -o git -g git \
		/home/git/gitlab/public/uploads \
		/home/git/gitlab/shared/pages \
		/home/git/gitlab/shared/artifacts \
		/home/git/gitlab/shared/lfs-objects	\
		/home/git/gitlab/shared/pages \
		/home/git/gitlab/shared/registry \
		/var/log/s6 \
		/var/log/gitlab
	mkdir -p /var/log/nginx
	# correct permissions of mount points
	chown -R git:git /etc/gitlab \
		/home/git/repositories \
		/var/log/gitlab \
		/home/git/gitlab/builds \
		/home/git/gitlab/shared
	# correct permission of tmp directory
	chmod 1777 /tmp
}

verify() {
	echo "Verifying gitlab installation..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:env:info RAILS_ENV=production
}

setup() {
	mkdir -p /etc/gitlab/gitlab
	create_db
	postgres_conf
	redis_conf
	install_conf
	setup_ssh
	prepare_dirs
	prepare_conf
	setup_gitlab
	verify
}

upgrade() {
	cd /home/git/gitlab
	echo "Migrating database.."
	su-exec git bundle exec rake db:migrate RAILS_ENV=production
	echo "Clearing caches.."
	su-exec git bundle exec rake cache:clear RAILS_ENV=production
	echo "Checking gitlab install.."
	su-exec git bundle exec rake gitlab:check RAILS_ENV=production
}

upgrade_check() {
	local current_version=$(cat /etc/gitlab/.version)
	if [ "$current_version" != "$GITLAB_VERSION" ]; then
		echo "GitLab version change detected.."
		upgrade
	fi
}

backup() {
	cd /home/git/gitlab
	echo "Creating GitLab backup.."
	su-exec git bundle exec rake gitlab:backup:create RAILS_ENV=production
}

logrotate() {
	echo "Rotating log files.."
	/usr/sbin/logrotate /etc/logrotate.d/gitlab
}

start() {
	if [ -f "/etc/gitlab/.version" ]; then
		echo "Configuration found"
		prepare_dirs
		install_conf
		prepare_conf
		rebuild_conf
		upgrade_check
	else
		echo "No configuration found. Running setup.."
		setup
	fi
	echo "$GITLAB_VERSION" > /etc/gitlab/.version
	echo "Starting Gitlab.."
	enable_services
	s6-svscan /run/s6
}

usage() {
    cat <<- EOF
	Usage: ${0##*/} [OPTION]
	Functions to operate on GitLab instance
	  start      start GitLab
	  setup      setup GitLab (used by docker build use with care)
	  upgrade    upgrade GitLab
	  backup     backup GitLab (excluding secrets.yml, gitlab.yml)
	  verify     verify Gitlab installation
	  logrotate  rotate logfiles
	  shell      enter interactive shell
	  usage      this help message
    EOF
}

case "${1:-usage}" in
	start) start ;;
	setup) setup ;;
	upgrade) upgrade ;;
	backup) backup ;;
	verify) verify ;;
	logrotate) logrotate ;;
	shell) /bin/sh ;;
	usage) usage ;;
	*) echo "Command \"$1\" is unknown."
		usage
		exit 1 ;;
esac
