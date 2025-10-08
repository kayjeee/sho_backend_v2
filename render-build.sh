#!/usr/bin/env bash
# render-build.sh

set -o errexit

echo "Unfreezing bundle..."
bundle config set frozen false

echo "Installing dependencies..."
bundle install

echo "Setting up secret key base..."
# Generate secret key if not set
if [ -z "$SECRET_KEY_BASE" ]; then
  export SECRET_KEY_BASE=$(rails secret)
  echo "Generated SECRET_KEY_BASE"
fi

echo "Precompiling assets..."
bundle exec rails assets:precompile

echo "Build completed successfully!"