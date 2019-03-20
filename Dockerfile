FROM alpine:latest

ENV GITLAB_VERSION 11.8.3

COPY files/ /

RUN  setup.sh

VOLUME [ "/home/git/repositories", "/etc/gitlab", "/var/log", "/home/git/gitlab/builds", "/home/git/gitlab/shared" ]

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
