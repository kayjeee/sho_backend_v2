# syntax=docker/dockerfile:1
# Production-ready Rails Dockerfile
# Build: docker build -t sho_backend_v2 .
# Run: docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value> --name sho_backend_v2 sho_backend_v2

ARG RUBY_VERSION=3.3.7
FROM ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

# Install base dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists/*

# Set Rails production environment
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

# ---------- Build Stage ----------
FROM base AS build

# Packages needed for building gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Copy Gemfiles and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy app code
COPY . .

# Precompile bootsnap for faster boot
RUN bundle exec bootsnap precompile app/ lib/

# Fix bin files for Linux
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Precompile assets without requiring RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---------- Final Stage ----------
FROM base

# Copy built gems and application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Copy entrypoint script BEFORE switching user
COPY bin/docker-entrypoint /rails/bin/docker-entrypoint
RUN chmod +x /rails/bin/docker-entrypoint

# Create non-root user and set ownership
RUN groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash rails && \
    chown -R rails:rails db log storage tmp

# Switch to non-root user
USER 1000:1000

# Entrypoint
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Expose port
EXPOSE 80

# Default command to run Rails server with Thruster
CMD ["./bin/thrust", "./bin/rails", "server"]
