#!/bin/sh

set -euo pipefail

mkdir -p /tmp/protobuf/src

wget -qO- https://github.com/protocolbuffers/protobuf/releases/download/v"$PROTOBUF_VERSION"/protobuf-ruby-"$PROTOBUF_VERSION".tar.gz |
	tar --strip-components=1 -z -x -C /tmp/protobuf/src

cd /tmp/protobuf/src

for patch in ../*.patch; do
	patch -p0 -i "$patch"
done

./configure && make

cd /tmp/protobuf/src/ruby/

rake genproto

gem build google-protobuf.gemspec
gem install --verbose google-protobuf-"$PROTOBUF_VERSION".gem
