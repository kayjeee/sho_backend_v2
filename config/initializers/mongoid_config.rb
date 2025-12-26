# config/initializers/mongoid_config.rb

# Globally configure Mongoid to prevent `find` and `find_by` from raising an
# exception when a document is not found. Instead, they will return `nil`.
# This is a critical setting for building a resilient API that can treat
# "not found" as a predictable state rather than an exceptional error.
Mongoid.raise_not_found_error = false

Rails.logger.info "✅ Mongoid `raise_not_found_error` set to false. `find` and `find_by` will now return nil for missing documents."
