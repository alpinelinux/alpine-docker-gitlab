FROM ruby:2.7-alpine3.13

ENV GITLAB_VERSION=14.0.2

COPY overlay /

RUN  setup.sh

EXPOSE 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
