#!/usr/bin/env bash
# render-build.sh

set -o errexit

echo "Installing dependencies..."
bundle install

echo "Precompiling assets..."
bundle exec rails assets:precompile

echo "Build completed successfully!"