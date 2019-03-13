FROM alpine:latest

COPY files/ /

RUN  setup.sh

VOLUME [ "/home/git/repositories", "/etc/gitlab", "/home/git/gitlab/log", "/home/git/gitlab/builds", "/home/git/gitlab/shared" ]

EXPOSE 22/tcp 8080/tcp

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]