FROM ruby:2.6-alpine

ENV GITLAB_VERSION=13.0.0

COPY overlay /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
