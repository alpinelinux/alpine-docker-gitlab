ARG ALPINE_VERSION
FROM curlimages/curl AS source

ARG GITLAB_SHELL_VERSION

WORKDIR /tmp/src
USER root

COPY build/fetch-source /usr/local/bin/
COPY build/lib/ /usr/local/lib/

RUN fetch-source

######################################################

FROM alpinelinux/golang:$ALPINE_VERSION as builder

WORKDIR /tmp/src
USER root

COPY --from=source /tmp/src /tmp/src
COPY build/build-gitlab-shell /usr/local/bin/
COPY build/lib/ /usr/local/lib/
COPY build/patches /tmp/

RUN build-gitlab-shell

######################################################

FROM alpine:$ALPINE_VERSION

COPY overlay/ /
COPY --from=builder /home/git/gitlab-shell/ /home/git/gitlab-shell/
COPY --from=builder /tmp/src/config.yml.example /usr/local/share/gitlab-shell/
COPY build/setup-image /usr/local/bin/

RUN setup-image

EXPOSE 22

WORKDIR /home/git/gitlab-shell
CMD entrypoint
