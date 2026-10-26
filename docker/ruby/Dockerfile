FROM ruby:4.0.9-slim-bookworm AS base

RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends build-essential pkg-config curl cmake libssl-dev libyaml-dev imagemagick \
    && rm -rf /var/lib/apt/lists/*

RUN echo 'gem: --no-document' >> ~/.gemrc

WORKDIR /app

COPY Gemfile* /app/

RUN bundle install --jobs $(nproc) --retry=3 && \
    bundle clean --force && rm -rf /usr/local/bundle/cache/*

# The bundle replaces the vulnerable default JSON gem (CVE-2026-33210).
RUN rm -rf /usr/local/lib/ruby/4.0.0/json* /usr/local/lib/ruby/4.0.0/*-linux/json \
    /usr/local/lib/ruby/gems/4.0.0/gems/json-* \
    /usr/local/lib/ruby/gems/4.0.0/specifications/default/json-*.gemspec

COPY . /app

FROM base AS tests
ENV RACK_ENV=test NO_RT_DEBUG=1
RUN bundle exec rspec
CMD ["bundle", "exec", "rspec"]

FROM ruby:4.0.9-slim-bookworm AS deploy
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends bash curl libssl-dev libyaml-0-2 imagemagick \
    && rm -rf /var/lib/apt/lists/*

COPY --from=base /usr/local/bundle /usr/local/bundle

# The bundle replaces the vulnerable default JSON gem (CVE-2026-33210).
RUN rm -rf /usr/local/lib/ruby/4.0.0/json* /usr/local/lib/ruby/4.0.0/*-linux/json \
    /usr/local/lib/ruby/gems/4.0.0/gems/json-* \
    /usr/local/lib/ruby/gems/4.0.0/specifications/default/json-*.gemspec

COPY --from=tests /app/spec/results /app/spec/results
COPY . /app

ENV RUBY_YJIT_ENABLE=1 \
    SERVER_ENV=production \
    RACK_ENV=production \
    PORT=7000

WORKDIR /app

HEALTHCHECK --interval=15s --timeout=2s --retries=3 CMD curl --fail http://127.0.0.1:$PORT/healthcheck || exit 1
CMD bundle exec rackup -o 0.0.0.0 -p $PORT -s falcon
