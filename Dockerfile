# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production" \
    RAILS_LOG_TO_STDOUT="1" \
    RAILS_SERVE_STATIC_FILES="1"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libpq5 postgresql-client build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

FROM base AS build

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p log tmp && \
    chown -R rails:rails db log tmp public/assets
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
