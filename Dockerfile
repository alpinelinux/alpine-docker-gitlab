ARG GITLAB_SHELL_VERSION
FROM alpinelinux/gitlab-shell:${GITLAB_SHELL_VERSION} as gitlab-shell

FROM ruby:2.7-alpine3.13

ENV GITLAB_VERSION=14.0.10

COPY overlay /

RUN  setup.sh

EXPOSE 80

COPY --from=gitlab-shell /home/git/gitlab-shell /home/git/gitlab-shell

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
