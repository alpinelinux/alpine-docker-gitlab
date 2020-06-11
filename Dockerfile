FROM ruby:2.6-alpine

ENV GITLAB_VERSION=12.10.11
ENV PROTOBUF_VERSION=3.11.4

COPY overlay /

RUN  setup.sh

EXPOSE 22 80

ENTRYPOINT [ "entrypoint.sh" ]

CMD [ "start" ]
