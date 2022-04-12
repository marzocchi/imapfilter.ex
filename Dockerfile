FROM elixir:1.13.3-alpine AS builder

COPY . /project
WORKDIR /project

ENV MIX_ENV=prod

RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get --only $MIX_ENV
RUN MIX_ENV=prod mix release --path /app

FROM elixir:1.13.3-alpine 

COPY --from=builder /app /app
WORKDIR /app

ENTRYPOINT ["/app/bin/imapfilter"]
CMD ["start"]