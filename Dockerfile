FROM alpine:latest

ENV GITLAB_VERSION 11.11.0

COPY overlay/ /

RUN  setup.sh

VOLUME [ "/home/git/repositories", "/etc/gitlab", "/var/log", "/home/git/gitlab/builds", "/home/git/gitlab/shared", "/home/git/gitlab/public/uploads" ]

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
