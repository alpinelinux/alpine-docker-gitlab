#!/bin/sh

wget -O- https://github.com/grpc/grpc/archive/v"$GRPC_VERSION".tar.gz |
tar zx -C /tmp/grpc

cd /tmp/grpc/grpc-"$GRPC_VERSION"

for patch in ../*.patch; do
    patch -p1 -i "$patch"
done

# Remove Werror from makefile
sed -i -e 's/-Werror//g' Makefile

# Remove some bundled dependencies from the gem's files list.
sed -i -e '/etc\/roots.pem/d' \
	-e '/third_party\/boringssl\//d' \
	-e '/third_party\/zlib\//d' \
	-e '/third_party\/cares\//d' \
	grpc.gemspec

# Remove unused dependency from gemspec.
sed -i -e '/add_dependency.*googleauth/d' \
        -e '/add_dependency.*googleapis-common-protos-types/d' \
        grpc.gemspec

export CPPFLAGS="$CPPFLAGS \
        -Wno-error=class-memaccess \
        -Wno-error=ignored-qualifiers \
        -Wno-error=maybe-uninitialized"

gem build grpc.gemspec
gem install --ignore-dependencies --verbose grpc-"$GRPC_VERSION".gem

