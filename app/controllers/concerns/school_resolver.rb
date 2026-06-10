module SchoolResolver
  extend ActiveSupport::Concern

  def find_school_by_id_or_slug(school_identifier)
    return nil if school_identifier.blank?

    if BSON::ObjectId.legal?(school_identifier)
      School.find_by(id: BSON::ObjectId.from_string(school_identifier))
    else
      clean_name = school_identifier.gsub('-', ' ')
      School.where(schoolName: /^#{Regexp.escape(clean_name)}$/i).first ||
      School.where(schoolEmail: /^#{Regexp.escape(school_identifier.to_s)}$/i).first
    end
  end
end
