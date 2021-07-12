FROM curlimages/curl AS source

ARG GITALY_SERVER_VERSION

WORKDIR /tmp/src
USER root

COPY overlay /

RUN setup fetch_source

######################################################

FROM alpinelinux/golang AS build-go

COPY --from=source /tmp/src /tmp/src
COPY overlay /

WORKDIR /tmp/src

USER root

RUN setup gitaly

######################################################

FROM alpinelinux/build-base AS build-git

COPY --chown=buildozer:buildozer --from=source /tmp/src /tmp/src
COPY overlay /

WORKDIR /tmp/src

RUN setup gitaly_git
