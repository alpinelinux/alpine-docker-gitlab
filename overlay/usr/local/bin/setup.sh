#!/bin/sh

set -eu

. /usr/local/lib/libsetup

gitlab_location=/home/git/gitlab
: ${PROTOBUF_VERSION:=}

# export so gitaly makefile does not set deployment to true
export BUNDLE_DEPLOYMENT=false
export MAKEFLAGS=-j$(nproc)

get_source() {
	local project=$1
	local version=$2
	local destination=$3
	# version can be a tag or sha
	[ "${#version}" != 40 ] && version="v$version"
	mkdir -p "$destination" && cd "$destination"
	git -c init.defaultBranch=master init
	git remote add origin https://gitlab.com/gitlab-org/$project.git
	git fetch --depth 1 origin $version
	git -c advice.detachedHead=false checkout FETCH_HEAD
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
apk add --no-cache --virtual .gitlab-runtime \
	git \
	su-exec \
	nodejs \
	postgresql-client \
	s6 \
	openssh \
	rsync \
	nginx \
	gnupg \
	logrotate \
	tzdata \
	graphicsmagick \
	lua5.3 \
	lua-mqtt-publish \
	lua-cjson

# add buildtime dependencies
apk add --no-cache --virtual .gitlab-buildtime \
	build-base \
	cmake \
	libxml2-dev \
	icu-dev \
	openssl-dev \
	postgresql-dev \
	linux-headers \
	re2-dev \
	c-ares-dev \
	yarn \
	go \
	bash

# 5 setup system user
adduser -D -g "GitLab" -s /bin/sh git
passwd -u git

# 6 Database
# we use a seperate container for database

# 7. Redis
# we use a seperate container for redis

echo "### Set system wide bundler settings ###"
bundle config set --global jobs $(nproc)
bundle config set --global silence_root_warning true
bundle config set --global force_ruby_platform true
# we do not use deployment and share gems via system
bundle config set --global deployment false
bundle config set --global without development test mysql aws kerberos
# https://github.com/protocolbuffers/protobuf/issues/2335#issuecomment-579913357
bundle config set --global build.google-protobuf --with-cflags=-D__va_copy=va_copy

#########
## gitlab
#########
echo "### Installing GitLab.. ###"
get_source gitlab-foss "$GITLAB_VERSION" "/home/git/gitlab"
# redir log directory
install -do git -g git /var/log/gitlab /var/log/s6
rm -rf "$gitlab_location"/log
ln -sf /var/log/gitlab "$gitlab_location"/log
# https://gitlab.com/gitlab-org/gitlab-foss/issues/47483
cd "$gitlab_location"
apply_patch -p0 -i /tmp/gitlab/disable-check-gitaly.patch
apply_patch -p0 -i /tmp/gitlab/puma-no-redirect.patch
apply_patch -p0 -i /tmp/gitlab/puma-socket-path.patch
apply_patch -p0 -i /tmp/logrotate/logrotate-defaults.patch
apply_patch -p0 -i /tmp/nginx/nginx-config.patch
apply_patch -p0 -i /tmp/resque/resque-config.patch

# temporary symlink the example configs to make setup happy
for config in gitlab.yml.example database.yml.postgresql; do
	ln -sf $config "$gitlab_location"/config/${config%.*}
done

# This needs to exist, otherwise gitlab will fail by trying to write to
# a symlink.
install -dm0755 /etc/gitlab/gitlab-shell/secret
echo 'changeme' >/etc/gitlab/gitlab-shell/secret/gitlab_shell_secret

# https://github.com/protocolbuffers/protobuf/pull/6848
if [ -n "$PROTOBUF_VERSION" ]; then
	echo "Building local protobuf version: $PROTOBUF_VERSION"
	sh /tmp/protobuf/build.sh
fi

cd "$gitlab_location"
bundle install

###################
## gitlab-workhorse
###################
echo "### Installing GitLab Workhorse.. ###"
# GITLAB_WORKHORSE_VERSION=$(cat "$gitlab_location"/GITLAB_WORKHORSE_VERSION)
# get_source gitlab-workhorse "$GITLAB_WORKHORSE_VERSION" "/home/git/src/gitlab-workhorse"
cd "$gitlab_location"/workhorse
make && make install

###############
## gitlab-pages
###############
echo "### Installing GitLab Pages.. ###"
GITLAB_PAGES_VERSION=$(cat "$gitlab_location"/GITLAB_PAGES_VERSION)
get_source gitlab-pages "$GITLAB_PAGES_VERSION" "/home/git/src/gitlab-pages"
cd /home/git/src/gitlab-pages
make
install ./gitlab-pages /usr/local/bin/gitlab-pages

echo "### Compiling gettex.. ###"
cd "$gitlab_location"
# https://gitlab.com/gitlab-org/gitlab-foss/issues/50937
export NODE_OPTIONS="--max_old_space_size=4096"
bundle exec rake gettext:compile RAILS_ENV=production

# compile assets (this is terrible slow)
echo "### Compiling GitLab assets.. ###"
cd "$gitlab_location"
yarn install --production --pure-lockfile
bundle exec rake gitlab:assets:compile RAILS_ENV=production NODE_ENV=production

echo "Build finish, cleaning up..."

_strip_binaries /usr/local/bin

# detect gem library depends and add them to world
gemdeps.sh | xargs -rt apk add --no-cache --virtual .gems-runtime

# remove all other build time deps
apk del .gitlab-buildtime

# remove build leftovers
rm -rf /home/git/src /tmp/*

# update git home permissions
chown -R git:git /home/git

# remove directories we dont need and take up lots of space
rm -rf /home/git/gitlab/node_modules \
    /home/git/gitlab/docker \
    /home/git/gitlab/qa \
    /root/.bundle \
    /root/.cache \
    /root/go \
    /var/cache/apk/* \
    /usr/local/share/.cache

# cleanup gems
gemdir=/usr/local/bundle
rm -rf "$gemdir"/cache
find "$gemdir" -type f \( -name "*.h" -o -name "*.c" -o -name "*.o" -o -name "*.log" -o -name "*.out" \) -delete
find "$gemdir"/gems/*/ext -type f ! -name "*.so" ! -name "*.rb" -delete
for cruft in test spec example licenses samples man doc docs CHANGELOG COPYING; do
	rm -rf "$gemdir"/gems/*/$cruft
done

# Prevent the generated secret from ending up in the image
rm -f .gitlab_shell_secret
ln -s /etc/gitlab/gitlab-shell/secret/gitlab_shell_secret /home/git/gitlab/.gitlab_shell_secret
