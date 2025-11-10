# syntax=docker/dockerfile:1
# Ruby on Rails 8 Dockerfile for Railway.com

ARG RUBY_VERSION=3.3.7
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /app

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
    nodejs \
    openssl \
  && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# -------------------------
# Install correct Bundler
# -------------------------
RUN gem install bundler -v "~> 2.6" --no-document

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_APP_CONFIG=/usr/local/bundle \
    PATH="/usr/local/bundle/bin:/app/bin:$PATH"

# -------------------------
# Install Gems
# -------------------------
COPY Gemfile Gemfile.lock ./
RUN bundle lock --remove-platform x64-mingw-ucrt
RUN bundle install && rm -rf ~/.bundle "${BUNDLE_PATH}"/ruby/*/cache

# -------------------------
# Copy the application
# -------------------------
COPY . .

# Ensure scripts are executable
RUN chmod +x bin/* && sed -i 's/\r$//g' bin/*
RUN chmod +x script/generate-ssl-certs.sh
RUN script/generate-ssl-certs.sh

# -------------------------
# Environment Variables
# -------------------------
ENV RAILS_ENV=production \
    RACK_ENV=production \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true \
    PORT=3000

# -------------------------
# Precompile assets (optional)
# -------------------------
RUN bundle exec rake assets:precompile || echo "Skipping asset precompilation"

# -------------------------
# Expose and run
# -------------------------
EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
