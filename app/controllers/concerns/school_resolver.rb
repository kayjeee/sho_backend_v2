module SchoolResolver
  extend ActiveSupport::Concern

  def find_school_by_id_or_slug(school_identifier)
    return nil if school_identifier.blank?

    identifier = school_identifier.to_s.strip

    if BSON::ObjectId.legal?(identifier)
      School.find_by(id: BSON::ObjectId.from_string(identifier))
    else
      name_pattern = school_name_pattern(identifier)

      School.any_of(
        { schoolName: name_pattern },
        { schoolEmail: /^#{Regexp.escape(identifier)}$/i },
        { user_email: /^#{Regexp.escape(identifier)}$/i },
        { user_id: identifier }
      ).first
    end
  end

  private

  def school_name_pattern(identifier)
    tokens = identifier
             .to_s
             .parameterize
             .split("-")
             .reject(&:blank?)
             .map { |token| Regexp.escape(token) }

    return /^#{Regexp.escape(identifier)}$/i if tokens.empty?

    /\A\s*#{tokens.join('\W+')}\s*\z/i
  end
end
