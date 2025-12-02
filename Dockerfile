FROM elixir:alpine

RUN apk update && \
    apk --no-cache add nodejs npm alpine-sdk erlang-dev

RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix archive.install hex phx_new --force

WORKDIR /app
