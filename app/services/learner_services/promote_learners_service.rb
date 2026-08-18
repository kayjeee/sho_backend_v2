# app/services/learner_services/promote_learners_service.rb
module LearnerServices
  class PromoteLearnersService
    ServiceResult = Struct.new(
      :success, :message, :stats, :promoted, :skipped, :failed, :errors,
      keyword_init: true
    )

    def initialize(
      school_id:,
      source_academic_year:,
      destination_academic_year:,
      source_grade_id:,
      destination_grade_id:,
      learner_ids:,
      user_id: nil
    )
      @school_id = school_id.to_s.strip
      @source_academic_year = source_academic_year.to_s.strip
      @destination_academic_year = destination_academic_year.to_s.strip
      @source_grade_id = source_grade_id.to_s.strip
      @destination_grade_id = destination_grade_id.to_s.strip
      @learner_ids = Array(learner_ids).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      @user_id = user_id
    end

    def call
      validation_errors = validate_inputs
      if validation_errors.any?
        return ServiceResult.new(
          success: false,
          message: "Validation failed: #{validation_errors.join(', ')}",
          stats: { total: @learner_ids.size, promoted_count: 0, skipped_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          skipped: [],
          failed: [],
          errors: validation_errors
        )
      end

      # Resolve school
      school = find_school(@school_id)
      if school.nil?
        return ServiceResult.new(
          success: false,
          message: "School not found with ID #{@school_id}",
          stats: { total: @learner_ids.size, promoted_count: 0, skipped_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          skipped: [],
          failed: [],
          errors: ["School not found"]
        )
      end

      # Resolve grades
      resolved_school_id = school.id.to_s
      source_grade = find_grade(@source_grade_id, resolved_school_id)
      destination_grade = find_grade(@destination_grade_id, resolved_school_id)

      if source_grade.nil? || destination_grade.nil?
        return ServiceResult.new(
          success: false,
          message: "Source or destination grade not found or does not belong to school",
          stats: { total: @learner_ids.size, promoted_count: 0, skipped_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          skipped: [],
          failed: [],
          errors: ["Invalid grade selections for this school"]
        )
      end

      promoted = []
      skipped = []
      failed = []

      @learner_ids.each do |learner_id|
        process_learner_promotion(
          learner_id: learner_id,
          school_id: resolved_school_id,
          source_grade: source_grade,
          destination_grade: destination_grade,
          promoted: promoted,
          skipped: skipped,
          failed: failed
        )
      end

      total_count = @learner_ids.size
      overall_success = failed.empty? && (promoted.any? || skipped.any?)

      ServiceResult.new(
        success: overall_success,
        message: "Promotion completed. #{promoted.size} promoted, #{skipped.size} skipped, #{failed.size} failed.",
        stats: {
          total: total_count,
          promoted_count: promoted.size,
          skipped_count: skipped.size,
          failed_count: failed.size
        },
        promoted: promoted,
        skipped: skipped,
        failed: failed,
        errors: failed.map { |f| f[:reason] }
      )
    rescue => e
      Rails.logger.error "❌ [PromoteLearnersService] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      ServiceResult.new(
        success: false,
        message: "An unexpected error occurred during promotion: #{e.message}",
        stats: { total: @learner_ids.size, promoted_count: 0, skipped_count: 0, failed_count: @learner_ids.size },
        promoted: [],
        skipped: [],
        failed: [],
        errors: [e.message]
      )
    end

    private

    def validate_inputs
      errors = []
      errors << "School ID is required" if @school_id.blank?
      errors << "Source academic year is required" if @source_academic_year.blank?
      errors << "Destination academic year is required" if @destination_academic_year.blank?
      errors << "Source grade ID is required" if @source_grade_id.blank?
      errors << "Destination grade ID is required" if @destination_grade_id.blank?
      errors << "Learner IDs list cannot be empty" if @learner_ids.empty?

      if @source_grade_id == @destination_grade_id && @source_academic_year == @destination_academic_year
        errors << "Source and destination grade and academic year cannot be identical"
      end

      errors
    end

    def find_school(identifier)
      return nil if identifier.blank?
      if BSON::ObjectId.legal?(identifier)
        School.find_by(id: BSON::ObjectId.from_string(identifier))
      else
        name_pattern = Regexp.new(Regexp.escape(identifier.to_s.gsub('-', ' ')), Regexp::IGNORECASE)
        School.where(
          "$or" => [
            { "schoolName" => name_pattern },
            { "school_name" => name_pattern },
            { "name" => name_pattern }
          ]
        ).first
      end
    rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
      nil
    end

    def find_grade(grade_id, school_id)
      return nil if grade_id.blank?
      gid_str = grade_id.to_s
      gid_bson = BSON::ObjectId.legal?(gid_str) ? BSON::ObjectId.from_string(gid_str) : nil

      grade = Grade.where(:id.in => [gid_str, gid_bson].compact).first
      return nil unless grade

      # Verify grade belongs to school
      return grade if grade.school_id.to_s == school_id.to_s
      nil
    rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
      nil
    end

    def process_learner_promotion(learner_id:, school_id:, source_grade:, destination_grade:, promoted:, skipped:, failed:)
      lid_str = learner_id.to_s
      lid_bson = BSON::ObjectId.legal?(lid_str) ? BSON::ObjectId.from_string(lid_str) : nil

      learner = Learner.where(:id.in => [lid_str, lid_bson].compact).first

      if learner.nil?
        failed << { id: learner_id, reason: "Learner not found" }
        return
      end

      # 1. School isolation check
      if learner.school_id.to_s != school_id.to_s
        failed << {
          id: learner.id.to_s,
          name: learner.full_name,
          accession_number: learner.accession_number,
          reason: "Learner does not belong to the specified school"
        }
        return
      end

      current_grade_id = (learner.try(:gradeId) || learner.try(:grade_id))&.to_s

      # 2. Duplicate promotion protection
      already_promoted = (
        learner.academic_year == @destination_academic_year && current_grade_id == destination_grade.id.to_s
      ) || (
        Array(learner.academic_history).any? do |h|
          h["destination_academic_year"].to_s == @destination_academic_year &&
            h["destination_grade_id"].to_s == destination_grade.id.to_s
        end
      )

      if already_promoted
        skipped << {
          id: learner.id.to_s,
          name: learner.full_name,
          accession_number: learner.accession_number,
          reason: "Learner has already been promoted to '#{destination_grade.name}' for academic year #{@destination_academic_year}"
        }
        return
      end

      # 3. Source grade check
      if current_grade_id != source_grade.id.to_s
        failed << {
          id: learner.id.to_s,
          name: learner.full_name,
          accession_number: learner.accession_number,
          reason: "Learner is currently in grade '#{learner.grade_name || current_grade_id}', not source grade '#{source_grade.name}'"
        }
        return
      end

      # 4. Perform atomic promotion
      learner.promote!(
        to_academic_year: @destination_academic_year,
        to_grade_id: destination_grade.id.to_s,
        from_academic_year: @source_academic_year,
        from_grade_id: source_grade.id.to_s,
        promoted_by: @user_id
      )

      promoted << {
        id: learner.id.to_s,
        name: learner.full_name,
        accession_number: learner.accession_number,
        grade_id: destination_grade.id.to_s,
        grade_name: destination_grade.name,
        academic_year: @destination_academic_year
      }
    rescue => e
      Rails.logger.error "❌ Error promoting learner #{learner_id}: #{e.message}"
      failed << {
        id: learner_id,
        reason: "Failed to promote learner: #{e.message}"
      }
    end
  end
end
