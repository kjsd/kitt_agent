ARG MIX_ENV="prod"

FROM hexpm/elixir:1.19.4-erlang-28.3-alpine-3.23.0 AS build

# install build dependencies
RUN apk add --no-cache build-base git python3 curl

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ARG MIX_ENV
ENV MIX_ENV="${MIX_ENV}"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mkdir config
COPY config/config.exs config/$MIX_ENV.exs config/

RUN mix deps.get --only $MIX_ENV

RUN mix assets.setup
COPY priv priv
COPY lib lib

# compile and build the release
RUN mix compile

COPY assets assets
RUN mix assets.deploy

# changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/
# uncomment COPY if rel/ exists
COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM alpine:3.23.0 AS app
RUN apk add --no-cache libstdc++ openssl ncurses-libs
RUN apk --no-cache add tzdata && cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    apk del tzdata

ARG MIX_ENV
ENV USER="elixir"

WORKDIR "/home/${USER}/app"
# Creates an unprivileged user to be used exclusively to run the Phoenix app
RUN \
  addgroup \
   -g 1000 \
   -S "${USER}" \
  && adduser \
   -s /bin/sh \
   -u 1000 \
   -G "${USER}" \
   -h "/home/${USER}" \
   -D "${USER}" \
  && su "${USER}"

# Everything from this line onwards will run in the context of the unprivileged user.
USER "${USER}"

COPY --from=build --chown="${USER}":"${USER}" /app/_build/"${MIX_ENV}"/rel/kitt_agent ./

RUN bin/migrate

ENTRYPOINT ["bin/server"]

# Usage:
#  * build: sudo docker image build -t elixir/my_app .
#  * shell: sudo docker container run --rm -it --entrypoint "" -p 127.0.0.1:4000:4000 elixir/my_app sh
#  * run:   sudo docker container run --rm -it -p 127.0.0.1:4000:4000 --name my_app elixir/my_app
#  * exec:  sudo docker container exec -it my_app sh
#  * logs:  sudo docker container logs --follow --tail 100 my_app

#CMD ["start"]
