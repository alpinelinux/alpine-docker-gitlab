#!/bin/sh

set -eu

# use docker env
gitlab_version=11.8.1
gitlab_location=/home/git/gitlab

export BUNDLE_JOBS=$(nproc)
export BUNDLE_FORCE_RUBY_PLATFORM=1
export MAKEFLAGS=-j$(nproc)

get_source() {
	local project=$1
	local version=$2
	local url=https://gitlab.com/gitlab-org/$project/-/archive/v$version/$project-v$version.tar.gz
	mkdir -p /home/git/src
	echo "Downloading: $1..."
	wget -O- "$url" | tar zx -C /home/git/src
}

####################################################################
# This follows the installation instructions from official docs
# but targetted at Alpine Linux
####################################################################

# 1. dependencies we use packages from stable repositories
# instead of building them our selves.
# 2. installing ruby including headers
# 3. install Go
# 4. install Node and Yarn
# upgrade system
apk -U upgrade --no-cache -a
# add runtime dependencies
apk add --no-cache --virtual .gitlab-runtime git su-exec ruby ruby-bundler \
	ruby-bigdecimal ruby-io-console ruby-webrick tzdata ruby-irb nodejs \
	postgresql-client s6 openssh nginx
# add buildtime dependencies
apk add --no-cache --virtual .gitlab-buildtime build-base cmake ruby-dev libxml2-dev \
	icu-dev openssl-dev postgresql-dev linux-headers re2-dev c-ares-dev yarn go

# 5 setup system user
adduser -D -g "GitLab" -s /sbin/nologin git

# 6 Database
# we use a seperate container for database

# 7. Redis
# we use a seperate container for redis

# 8. Install gitlab
get_source gitlab-ce "$gitlab_version"
mv /home/git/src/gitlab-ce-v$gitlab_version "$gitlab_location"

# https://gitlab.com/gitlab-org/gitlab-ce/issues/47483
cd "$gitlab_location"
patch -p0 -i /tmp/gitlab/disable-check-gitaly.patch

# needed configs by setup process
initial_config="
	gitlab.yml.example
	secrets.yml.example
	unicorn.rb.example
	initializers/rack_attack.rb.example
	resque.yml.example
	database.yml.postgresql
	"
for config in $initial_config; do
	if [ ! -f "$gitlab_location/config/${config%.*}" ]; then
		ln -sf "$gitlab_location"/config/$config \
			"$gitlab_location"/config/${config%.*}
	fi
done

# gprc is a nightmare so we build and install our own
sh /tmp/grpc/build.sh

# install gems to system so they are shared with gitaly
cd "$gitlab_location"
bundle install --system --without development test mysql aws kerberos

###############
## gitlab-shell
###############
GITLAB_SHELL_VERSION=$(cat "$gitlab_location"/GITLAB_SHELL_VERSION)
get_source gitlab-shell $GITLAB_SHELL_VERSION
mv /home/git/src/gitlab-shell-v$GITLAB_SHELL_VERSION /home/git/gitlab-shell
cd /home/git/gitlab-shell
install -Dm644 config.yml.example "$gitlab_location"/gitlab-shell/config.yml
ln -sf "$gitlab_location"/gitlab-shell/config.yml config.yml
./bin/compile && ./bin/install

###################
## gitlab-workhorse
###################
GITLAB_WORKHORSE_VERSION=$(cat "$gitlab_location"/GITLAB_WORKHORSE_VERSION)
get_source gitlab-workhorse $GITLAB_WORKHORSE_VERSION
cd /home/git/src/gitlab-workhorse-v$GITLAB_WORKHORSE_VERSION
make && make install

###############
## gitlab-pages
###############
GITLAB_PAGES_VERSION=$(cat "$gitlab_location"/GITLAB_PAGES_VERSION)
get_source gitlab-pages $GITLAB_PAGES_VERSION
cd /home/git/src/gitlab-pages-v$GITLAB_PAGES_VERSION
make
install ./gitlab-pages /usr/local/bin/gitlab-pages

#########
## gitaly
## will also install ruby gems into system like gitlab
#########
GITALY_SERVER_VERSION=$(cat "$gitlab_location"/GITALY_SERVER_VERSION)
get_source gitaly $GITALY_SERVER_VERSION
cd /home/git/src/gitaly-v$GITALY_SERVER_VERSION
make install BUNDLE_FLAGS=--system
mv ruby /home/git/gitaly-ruby
install -Dm644 config.toml.example "$gitlab_location"/gitaly/config.toml

# compile gettext
cd "$gitlab_location"
bundle exec rake gettext:compile RAILS_ENV=production

# compile assets (this is terrible slow)
cd "$gitlab_location"
yarn install --production --pure-lockfile
bundle exec rake gitlab:assets:compile RAILS_ENV=production NODE_ENV=production

# Cleanup TODO
# remove build artifacts
# remove build deps (apply logic to keep runtime deps)
# update permissions

gemdeps.sh | xargs -rt apk add --no-cache --virtual .gems-runtime
apk del .gitlab-buildtime
rm -rf /home/git/src /tmp/*
chown -R git:git /home/git
# remove directories we dont need and take up lots of space
gemdir="$(ruby -e 'puts Gem.default_dir')"
rm -rf /home/git/gitlab/node_modules \
    /home/git/gitlab/docker \
    /home/git/gitlab/qa \
    /root/.bundle \
    /root/.cache \
    /var/cache/apk/* \
    /home/git/gitlab-shell/go \
    /home/git/gitlab-shell/go_build \
    /usr/local/share/.cache \
    $gemdir/cache

find $gemdir/gems -name "*.o" -delete
find $gemdir/gems -name "*.so" -delete

