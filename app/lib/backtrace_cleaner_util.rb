module BacktraceCleanerUtil
  def self.clean(backtrace)
    return [] if backtrace.nil? || !backtrace.is_a?(Array) || backtrace.empty?

    # Try using Rails' backtrace cleaner if available
    cleaned = if Rails.respond_to?(:backtrace_cleaner) && Rails.backtrace_cleaner
                Rails.backtrace_cleaner.clean(backtrace)
              else
                []
              end

    # If standard cleaner is empty or filters out too much, filter specifically for app files
    if cleaned.blank?
      cleaned = backtrace.select do |line|
        line.include?("/app/") || line.include?("/lib/") || line.include?("/config/") || line.include?("/test/")
      end
    end

    # Explicitly filter out any lines containing standard gem/library directories to avoid showing rbenv/gems
    cleaned = cleaned.reject do |line|
      line.include?("/gems/") ||
        line.include?("/.rbenv/") ||
        line.include?("/usr/local/lib/") ||
        line.include?("active_support") ||
        line.include?("action_pack") ||
        line.include?("puma") ||
        line.include?("rack") ||
        line.include?("railties")
    end

    # Last resort fallback if everything was filtered out: first 10 lines of the original backtrace
    cleaned = backtrace.first(10) if cleaned.blank?

    cleaned
  end
end
