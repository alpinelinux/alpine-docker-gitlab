ARG GOAWAY_VERSION=0.7.0
ARG ALPINE_VERSION=3.21
FROM git.gammaspectra.live/git/go-away:${GOAWAY_VERSION}-alpine${ALPINE_VERSION}

COPY overlay /

RUN <<EOF
apk add su-exec
adduser -D go-away
install -dm0755 /etc/go-away
install -dm0755 -ogo-away -ggo-away /var/cache/go-away
EOF

EXPOSE 8080/tcp

VOLUME /var/cache/go-away

ENTRYPOINT ["/usr/local/bin/entrypoint"]
