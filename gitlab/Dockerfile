FROM ruby:2.6-alpine

ENV GITLAB_VERSION=12.2.9
ARG GRPC_VERSION=1.19.0

COPY gitlab/overlay/ /

RUN  setup.sh

VOLUME [ "/home/git/repositories", "/etc/gitlab", "/var/log", "/home/git/gitlab/builds", "/home/git/gitlab/shared", "/home/git/gitlab/public/uploads" ]

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
