# frozen_string_literal: true

# --- Set Gemfile path ---
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

# --- Load gems from Gemfile ---
require "bundler/setup"

# --- Speed up boot time with Bootsnap ---
require "bootsnap/setup"

# --- Skip ActiveRecord if using Mongoid only ---
if ENV["SKIP_DB"]
  module ActiveRecord
    class Base
      def self.establish_connection(*); end
    end
  end
end
