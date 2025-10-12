# syntax=docker/dockerfile:1

# Specify Ruby version
ARG RUBY_VERSION=3.3.7
FROM ruby:$RUBY_VERSION-slim AS base

# Set working directory
WORKDIR /rails

# Install dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      nodejs \
      yarn \
      git \
      build-essential \
      libyaml-dev \
      pkg-config \
      postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Set default environment for production
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Copy Gemfiles and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3

# Copy the rest of the app
COPY . .

# Copy database.yml explicitly (important for Rails in Docker)
COPY config/database.yml config/database.yml

# Precompile bootsnap code for faster load times
RUN bundle exec bootsnap precompile app/ lib/

# Precompile assets (dummy secret for local builds)
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

# Create non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails && \
    chown -R rails:rails db log storage tmp config

USER 1000:1000

# Default environment variables (can be overridden at runtime)
ENV MONGODB_URI="mongodb://host.docker.internal:27017/sho_dev"
ENV RAILS_MASTER_KEY="dummy_master_key_for_local"
ENV PORT=4000
ENV RAILS_ENV="development"

# Entrypoint
ENTRYPOINT ["bin/rails"]

# Expose Rails port
EXPOSE 4000

# Default command to start server in development mode
CMD ["server", "-b", "0.0.0.0", "-p", "4000"]
