FROM curlimages/curl AS source

ARG GITLAB_SHELL_VERSION

WORKDIR /tmp/src
USER root

COPY build/fetch-source /usr/local/bin/
COPY build/lib/ /usr/local/lib/

RUN fetch-source

######################################################

FROM alpinelinux/golang as builder

WORKDIR /tmp/src
USER root

COPY --from=source /tmp/src /tmp/src
COPY build/build-gitlab-shell /usr/local/bin/
COPY build/lib/ /usr/local/lib/
COPY build/patches /tmp/

RUN build-gitlab-shell
