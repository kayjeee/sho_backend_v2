# app/services/grade_creation_service.rb
class GradeCreationService
  def self.create_from_metadata(user, metadata)
    grades    = Array.wrap(metadata["grades"]).compact
    school_id = metadata["schoolId"]

    return false unless grades.any? && school_id.present?

    current_year        = Date.current.year
    academic_year_start = Date.new(current_year, 1, 1)
    academic_year_end   = Date.new(current_year, 12, 31)

    created_any = false

    grades.each do |grade_name|
      begin
        grade = Grade.where(name: grade_name, school_id: school_id).first_or_create!(
          grade_level: grade_name.to_s,
          description: "Auto-created during onboarding",
          capacity: 30,
          status: 0,
          min_age: 5,
          max_age: 18,
          fees: 0.0,
          academic_year_start: academic_year_start,
          academic_year_end: academic_year_end,
          curriculum_info: {},
          schedule_info: {}
        )
        Rails.logger.info "✅ Grade '#{grade_name}' ensured for school #{school_id} (id: #{grade.id})"
        created_any = true
      rescue => e
        Rails.logger.error "🔥 Error creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
      end
    end

    if created_any
      user.set("onboarding_status.createGrades" => true)
    end

    created_any
  end
end
