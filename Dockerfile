ARG GITLAB_SHELL_VERSION
FROM alpinelinux/gitlab-shell:${GITLAB_SHELL_VERSION} as gitlab-shell

FROM ruby:2.7-alpine3.13

ARG GITLAB_VERSION
ENV GITLAB_VERSION=$GITLAB_VERSION

COPY overlay /

RUN  setup.sh

EXPOSE 80

COPY --from=gitlab-shell /home/git/gitlab-shell /home/git/gitlab-shell

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
