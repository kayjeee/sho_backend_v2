# config/initializers/mongoid_configuration.rb
#
# Globally configure Mongoid to align with more defensive finder behavior.

# By default, Mongoid's `find` method raises a `Mongoid::Errors::DocumentNotFound`
# error if no document matches the provided ID. This can cause frequent crashes in
# controllers and services, especially in systems where a user can exist in an
# external provider (like Auth0) before they exist in the local database.
#
# Setting `raise_not_found_error` to `false` changes this behavior globally.
# When `false`, `find` will return `nil` if no document is found, behaving
# identically to `find_by`. This prevents exceptions for missing documents and
# encourages a more defensive coding pattern where developers must explicitly
# handle `nil` return values. This is critical for building a resilient API
# that can handle "user not found" as a state, not an exception.
#
Mongoid.raise_not_found_error = false

# Log confirmation that this setting has been applied on application boot.
Rails.logger.info "✅ Mongoid.raise_not_found_error configured to false. `find` will now return nil for missing documents."
