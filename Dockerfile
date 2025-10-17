# syntax=docker/dockerfile:1
# Optimized Rails 8 Dockerfile for Fly.io
# Build locally: docker build -t sho_backend_v2 .
# Run locally: docker run -p 8080:8080 -e RAILS_MASTER_KEY=<key> -e DB_NAME=<db> -e DB_USERNAME=<user> -e DB_PASSWORD=<pass> sho_backend_v2

ARG RUBY_VERSION=3.3.7
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# -------------------------
# System dependencies
# -------------------------
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libjemalloc2 \
    libvips \
    pkg-config \
    libyaml-dev \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# -------------------------
# Install correct Bundler
# -------------------------
RUN gem install bundler -v "~> 2.6" --no-document

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    PATH="/usr/local/bundle/bin:/rails/bin:$PATH"

# -------------------------
# Install Gems
# -------------------------
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache

# -------------------------
# Copy the application
# -------------------------
COPY . .

# Make scripts executable & fix Windows line endings
RUN chmod +x bin/* && \
    sed -i 's/\r$//g' bin/* && \
    sed -i 's/ruby\.exe/ruby/g' bin/*

# -------------------------
# Build assets for production (skip DB)
# -------------------------
FROM base AS build

ENV RAILS_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_DEPLOYMENT=1 \
    SECRET_KEY_BASE_DUMMY=1 \
    SKIP_DB=true \
    RAILS_SERVE_STATIC_FILES=true

# Precompile assets without connecting to DB
RUN bin/rails assets:precompile

# -------------------------
# Final production image
# -------------------------
FROM ruby:$RUBY_VERSION-slim AS production

WORKDIR /rails

RUN apt-get update -qq && apt-get install --no-install-recommends -y \
    libjemalloc2 \
    libvips \
  && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    PORT=8080 \
    PATH="/usr/local/bundle/bin:/rails/bin:$PATH"

# Copy built app + gems
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Create non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails && \
    chown -R rails:rails /rails

USER rails

EXPOSE 8080

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "8080"]
