#!/bin/sh

set -eu

# https://gitlab.com/gitlab-org/omnibus-gitlab/merge_requests/1707
export RUBYOPT="${RUBYOPT:---disable-gems}"
export RAILS_ENV="${RAILS_ENV:-production}"
: "${POSTGRES_DB:=$POSTGRES_USER}"
: "${GITLAB_SERVICES:=nginx sidekiq workhorse puma}"

# base config files found in gitlab/config dir
BASECONF="
	gitlab/gitlab.yml.example
	gitlab/secrets.yml.example
	gitlab/puma.rb.example
	gitlab/resque.yml.example
	gitlab/initializers/rack_attack.rb.example
"

create_db() {
	export PGPASSWORD=$POSTGRES_PASSWORD
	echo "Connecting to postgres.."
	while ! pg_isready -qh postgres; do sleep 1; done
	echo "Connection succesful"
	psql -h postgres -U $POSTGRES_USER -d $POSTGRES_DB \
		-c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
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
	rm -rf /run/s6 && mkdir -p /run/s6
	for srv in $GITLAB_SERVICES; do
		ln -sf /etc/s6/$srv /run/s6/$srv
	done
}

prepare_conf() {
	echo "Preparing configuration.."
	link_config "/etc/gitlab/gitlab" "/home/git/gitlab/config"
	link_config "/etc/gitlab/nginx" "/etc/nginx"
}

rebuild_conf() {
	if [ ! -f "/home/git/.ssh/authorized_keys" ]; then
		echo "Rebuild gitlab-shell configuration files.."
		cd /home/git/gitlab
		force=yes su-exec git \
			bundle exec rake gitlab:shell:setup
	fi
}

postgres_conf() {
	cat <<- EOF > /etc/gitlab/gitlab/database.yml
	production:
	  adapter: postgresql
	  encoding: unicode
	  database: $POSTGRES_DB
	  pool: 10
	  username: $POSTGRES_USER
	  password: "$POSTGRES_PASSWORD"
	  host: postgres
	EOF
}

workhorse_conf() {
	mkdir -p /etc/gitlab/workhorse
	cat <<- EOF >/etc/gitlab/workhorse/config.toml
	[redis]
	URL = "tcp://redis:6379"
	EOF
}

setup_gitlab() {
	echo "Setting up gitlab..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:setup force=yes
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
		/home/git/run/gitlab \
		/var/log/s6 \
		/var/log/gitlab
	mkdir -p /var/log/nginx
	# correct permissions of mount points
	chown -R git:git /etc/gitlab \
		/home/git/repositories \
		/var/log/gitlab \
		/home/git/gitlab/builds \
		/home/git/gitlab/shared
	# logrotate need to be owned by root
	chown root:root /etc/gitlab/logrotate/gitlab
	# correct permission of tmp directory
	chmod 1777 /tmp
}

verify() {
	echo "Verifying gitlab installation..."
	cd /home/git/gitlab
	su-exec git bundle exec rake gitlab:env:info
}

setup() {
	mkdir -p /etc/gitlab/gitlab
	create_db
	postgres_conf
	install_conf
	workhorse_conf
	prepare_dirs
	prepare_conf
	setup_gitlab
	verify
}

upgrade() {
	cd /home/git/gitlab
	echo "Migrating database.."
	su-exec git bundle exec rake db:migrate
	echo "Clearing caches.."
	su-exec git bundle exec rake cache:clear
	echo "Checking gitlab install.."
	su-exec git bundle exec rake gitlab:check
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
	su-exec git bundle exec rake gitlab:backup:create SKIP=$GITLAB_BACKUP_SKIP
}

dump_db() {
	cd /home/git/gitlab
	echo "Dumping GitLab database.."
	local today="$(date +%Y-%m-%d)"
	mkdir -p /home/git/backup
	PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --create --format c \
		--host=postgres --user="$POSTGRES_USER" --dbname="$POSTGRES_DB" > \
		/home/git/backup/"$POSTGRES_DB-$today".db
	echo "Finished dumping: $POSTGRES_DB-$today.db"
}

logrotate() {
	echo "Rotating log files.."
	/usr/sbin/logrotate /etc/gitlab/logrotate/gitlab
}

cleanup() {
	echo "Removing older CI build logs.."
	find /home/git/gitlab/shared/artifacts -type f -mtime +30 -name "*.log" -delete
}

start() {
	if [ -f "/etc/gitlab/.version" ]; then
		echo "Configuration found"
		install_conf
		prepare_dirs
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
	  dump       dump database in /home/git/backup
	  verify     verify Gitlab installation
	  logrotate  rotate logfiles
	  cleanup    remove older CI log files
	  shell      enter interactive shell
	  help       this help message
	EOF
}

case "${1:-help}" in
	start) start ;;
	setup) setup ;;
	upgrade) upgrade ;;
	backup) backup ;;
	dump) dump_db ;;
	verify) verify ;;
	logrotate) logrotate ;;
	cleanup) cleanup ;;
	shell) /bin/sh ;;
	help) usage ;;
	*) echo "Command \"$1\" is unknown."
		usage
		exit 1 ;;
esac
