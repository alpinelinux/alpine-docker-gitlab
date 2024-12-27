ARG ALPINE_VERSION
ARG RUBY_VERSION
ARG GITLAB_SHELL_VERSION
ARG GITALY_SERVER_VERSION
FROM alpinelinux/gitlab-shell:${GITLAB_SHELL_VERSION} AS gitlab-shell
FROM alpinelinux/gitaly:$GITALY_SERVER_VERSION AS gitaly

FROM ruby:$RUBY_VERSION-alpine$ALPINE_VERSION

ARG GITLAB_VERSION
ENV GITLAB_VERSION=$GITLAB_VERSION

COPY overlay /
COPY --from=gitlab-shell /home/git/gitlab-shell /home/git/gitlab-shell
COPY --from=gitaly /usr/local/bin/gitaly-backup /usr/local/bin/gitaly-backup

RUN setup.sh

EXPOSE 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
