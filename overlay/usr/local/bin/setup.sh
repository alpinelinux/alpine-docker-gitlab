#!/bin/sh

set -eu

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
	tzdata

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
	go

# 5 setup system user
adduser -D -g "GitLab" -s /bin/sh git
passwd -u git

# 6 Database
# we use a seperate container for database

# 7. Redis
# we use a seperate container for redis

#########
## gitlab
#########
get_source gitlab-ce "$GITLAB_VERSION"
mv /home/git/src/gitlab-ce-v$GITLAB_VERSION "$gitlab_location"
# redir log directory
install -do git -g git /var/log/gitlab /var/log/s6
rm -rf "$gitlab_location"/log
ln -sf /var/log/gitlab "$gitlab_location"/log
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
bundle install --without development test mysql aws kerberos

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
# gitlab-shell will not set PATH
ln -s /usr/local/bin/ruby /usr/bin/ruby

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
git clone https://gitlab.com/gitlab-org/gitaly.git -b \
        v$GITALY_SERVER_VERSION /home/git/src/gitaly
cd /home/git/src/gitaly
make install BUNDLE_FLAGS=--system
mv ruby /home/git/gitaly-ruby
install -Dm644 config.toml.example "$gitlab_location"/gitaly/config.toml

# https://gitlab.com/gitlab-org/gitlab-ce/issues/50937
export NODE_OPTIONS="--max_old_space_size=4096"

# compile gettext
cd "$gitlab_location"
bundle exec rake gettext:compile RAILS_ENV=production

# compile assets (this is terrible slow)
cd "$gitlab_location"
yarn install --production --pure-lockfile
bundle exec rake gitlab:assets:compile RAILS_ENV=production NODE_ENV=production

echo "Build finish, cleaning up..."

# strip go bins
for bin in /usr/local/bin/*; do
	[ "${bin##*.}" = sh ] && continue
	strip "$bin" || true
done

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
    /home/git/gitlab-shell/go \
    /home/git/gitlab-shell/go_build \
    /usr/local/share/.cache

# cleanup gems
gemdir=/usr/local/bundle
rm -rf "$gemdir"/cache
find "$gemdir"/extensions -name mkmf.log -delete -o -name gem_make.out -delete
find "$gemdir"/gems -name "*.o" -delete -o \( -iname "*.so" ! -iname "libsass.so" \) -delete
for cruft in test spec example licenses samples man ports doc docs CHANGELOG COPYING; do
	rm -rf "$gemdir"/gems/*/$cruft
done

# need to keep libsass
for dir in "$gemdir"/gems/*/ext; do
	case $dir in
		*sassc*) continue ;;
		*) rm -rf "$dir" ;;
	esac
done
