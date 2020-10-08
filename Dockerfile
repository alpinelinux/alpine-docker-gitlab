FROM ruby:2.6-alpine3.12

ENV GITLAB_VERSION=13.2.10

COPY overlay /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
