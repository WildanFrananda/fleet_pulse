# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.2-erlang-29.0.3-debian-trixie-20260713-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260713-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20260713-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.3
ARG DEBIAN_VERSION=trixie-20260713-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}@sha256:6fcd8ea864221b960c1ec418e3b10fa488298ff9e70c9e0f3db18070e610fb8a"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./

RUN set -eu; \
    lock="$(grep '"daisyui"' mix.lock)"; \
    sha="$(printf '%s' "$lock" | sed -n 's/.*daisyui\.git", "\([0-9a-f]\{40\}\)".*/\1/p')"; \
    tag="$(printf '%s' "$lock" | sed -n 's/.*tag: "\([^"]*\)".*/\1/p')"; \
    test -n "$sha" && test -n "$tag" || { echo "could not read the daisyui tag/commit from mix.lock"; exit 1; }; \
    git clone --depth 1 --branch "$tag" --quiet https://github.com/saadeghi/daisyui.git deps/daisyui; \
    got="$(git -C deps/daisyui rev-parse HEAD)"; \
    test "$got" = "$sha" || { echo "tag $tag resolves to $got, but mix.lock pins $sha"; exit 1; }; \
    test -f deps/daisyui/packages/bundle/daisyui.js

RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY bin ./bin

# The wire contracts and the Elixir generated from them. Both are build outputs now: the .proto
# came from a copy in this repository and the .pb.ex was committed beside it, so a field renamed
# in the contract changed nothing here until somebody noticed.
#
# `package_prefix` keeps the module names the server code already uses
# (FleetPulse.Proto.Fleet.V1.*), so this is a change of SOURCE, not a rename of everything.
RUN apt-get update \
  && apt-get install --no-install-recommends -y git protobuf-compiler libprotobuf-dev \
  && rm -rf /var/lib/apt/lists/* \
  && sh bin/sync-contracts \
  && mix escript.install hex protobuf --force \
  && mkdir -p lib/fleet_pulse/proto \
  && PATH="$PATH:/root/.mix/escripts" protoc \
       --elixir_out=plugins=grpc,package_prefix=fleet_pulse.proto:lib/fleet_pulse/proto \
       -I .contracts/proto \
       -I "$(dpkg -L libprotobuf-dev 2>/dev/null | grep -m1 'timestamp.proto' | sed 's|/google/protobuf/timestamp.proto||')" \
       .contracts/proto/common/v1/common.proto \
       .contracts/proto/fleet/v1/fleet.proto \
       .contracts/proto/shipping/v1/shipping.proto \
  && test -n "$(find lib/fleet_pulse/proto -name '*.pb.ex' | head -1)" \
     || { echo 'protoc produced no Elixir; the build would ship without wire types'; exit 1; }

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

RUN npm ci --prefix assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/fleet_pulse ./

USER nobody


# Probe the endpoint the service actually ships. This used to run `Repo.query!("SELECT 1")` over
# `fleet_pulse rpc`, which asked the same question of the database but never touched /health/ready
# — so the endpoint every other service is probed on sat unexercised here and could rot unnoticed.
# curl is in the runner image for this one purpose.
HEALTHCHECK --interval=10s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS http://127.0.0.1:4000/health/ready > /dev/null || exit 1

CMD ["/app/bin/server"]
