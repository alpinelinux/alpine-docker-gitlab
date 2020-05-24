#!/bin/sh

set -euo pipefail

mkdir -p /tmp/protobuf

wget -qO- https://github.com/protocolbuffers/protobuf/releases/download/v"$PROTOBUF_VERSION"/protobuf-ruby-"$PROTOBUF_VERSION".tar.gz |
	tar --strip-components=1 -z -x -C /tmp/protobuf

cd /tmp/protobuf/ruby/

for patch in ../*.patch; do
    patch -p0 -i "$patch"
done

gem build google-protobuf.gemspec
gem install --ignore-dependencies --verbose google-protobuf-"$PROTOBUF_VERSION".gem

