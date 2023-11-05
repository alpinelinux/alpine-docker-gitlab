ARG ALPINE_VERSION
ARG RUBY_VERSION
FROM curlimages/curl AS source

ARG GITALY_SERVER_VERSION

WORKDIR /tmp/src
USER root

COPY build/lib/ /usr/local/lib/
COPY build/fetch-source /usr/local/bin/

RUN fetch-source

######################################################

FROM registry.alpinelinux.org/alpine/infra/docker/golang:$ALPINE_VERSION AS build-gitaly

COPY --from=source /tmp/src /tmp/src
COPY build/lib/ /usr/local/lib/
COPY build/patches/ /tmp/patches/
COPY build/build-gitaly /usr/local/bin/

WORKDIR /tmp/src

USER root

RUN build-gitaly

######################################################

FROM alpinelinux/build-base:$ALPINE_VERSION AS build-git

COPY --chown=buildozer:buildozer --from=source /tmp/src /tmp/src
COPY build/patches/ /tmp/patches/
COPY build/lib/ /usr/local/lib/
COPY build/build-git /usr/local/bin/

WORKDIR /tmp/src

RUN build-git

######################################################

FROM ruby:$RUBY_VERSION-alpine$ALPINE_VERSION

COPY overlay /
COPY build/setup-image /usr/local/bin/

COPY --from=build-gitaly /tmp/gitaly /
COPY --from=build-gitaly /tmp/src/config.toml.example /usr/local/share/gitaly/
COPY --from=build-git /tmp/git/ /

RUN setup-image

USER git
WORKDIR /home/git

CMD entrypoint
