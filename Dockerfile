ARG GITLAB_SHELL_VERSION
FROM alpinelinux/gitlab-shell:${GITLAB_SHELL_VERSION} as gitlab-shell

FROM ruby:2.7-alpine3.14

ARG GITLAB_VERSION
ENV GITLAB_VERSION=$GITLAB_VERSION

COPY overlay /
COPY --from=gitlab-shell /home/git/gitlab-shell /home/git/gitlab-shell

RUN  setup.sh

EXPOSE 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
