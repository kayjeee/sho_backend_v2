# syntax=docker/dockerfile:1
# Multi-stage Rails Dockerfile for Development & Production
# Build production: docker build -t sho_backend_v2 .
# Run production: docker run -d -p 80:80 -e RAILS_MASTER_KEY=<key> -e MONGODB_URI=<uri> sho_backend_v2
# Build development: docker build --target development -t sho_backend_dev .
# Run development: docker run -it -p 4000:4000 --env-file .env sho_backend_dev

ARG RUBY_VERSION=3.3.7
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# -------------------------
# Base dependencies
# -------------------------
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips sqlite3 build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

# -------------------------
# Install correct Bundler
# -------------------------
RUN gem install bundler -v '~> 2.6' --no-document

ENV BUNDLE_PATH=/usr/local/bundle \
    PATH="/usr/local/bundle/bin:/rails/bin:$PATH" \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# -------------------------
# Copy Gemfiles and install gems
# -------------------------
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache

# -------------------------
# Copy application code
# -------------------------
COPY . .

# Ensure binstubs are executable and Linux-friendly
RUN chmod +x bin/* && \
    sed -i 's/\r$//g' bin/* && \
    sed -i 's/ruby\.exe/ruby/g' bin/*

# -------------------------
# Development Stage
# -------------------------
FROM base AS development

ENV RAILS_ENV=development \
    PORT=4000 \
    BUNDLE_WITHOUT=""

EXPOSE 4000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "4000"]

# -------------------------
# Production Build Stage
# -------------------------
FROM base AS build

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT=1

# Precompile bootsnap and assets
RUN bundle exec bootsnap precompile --gemfile && \
    bundle exec bootsnap precompile app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# -------------------------
# Production Final Stage
# -------------------------
FROM ruby:$RUBY_VERSION-slim AS production

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    PATH="/usr/local/bundle/bin:/rails/bin:$PATH" \
    MONGODB_URI="" \
    RAILS_MASTER_KEY=""

# Copy built gems and application from build stage
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Copy entrypoint
COPY bin/docker-entrypoint /rails/bin/docker-entrypoint
RUN chmod +x /rails/bin/docker-entrypoint || true

# Create non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails && \
    chown -R rails:rails db log storage tmp || true

USER 1000:1000

EXPOSE 80

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "80"]
