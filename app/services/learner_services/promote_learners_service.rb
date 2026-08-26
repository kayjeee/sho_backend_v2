# app/services/learner_services/promote_learners_service.rb
module LearnerServices
  class PromoteLearnersService
    ServiceResult = Struct.new(
      :success, :message, :summary, :promoted, :already_promoted,
      :wrong_grade, :not_found_or_unauthorized, :errors,
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
          summary: { promoted_count: 0, already_promoted_count: 0, wrong_grade_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          already_promoted: [],
          wrong_grade: [],
          not_found_or_unauthorized: @learner_ids,
          errors: validation_errors
        )
      end

      # Resolve school
      school = find_school(@school_id)
      if school.nil?
        return ServiceResult.new(
          success: false,
          message: "School not found with ID #{@school_id}",
          summary: { promoted_count: 0, already_promoted_count: 0, wrong_grade_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          already_promoted: [],
          wrong_grade: [],
          not_found_or_unauthorized: @learner_ids,
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
          summary: { promoted_count: 0, already_promoted_count: 0, wrong_grade_count: 0, failed_count: @learner_ids.size },
          promoted: [],
          already_promoted: [],
          wrong_grade: [],
          not_found_or_unauthorized: @learner_ids,
          errors: ["Invalid grade selections for this school"]
        )
      end

      promoted = []
      already_promoted = []
      wrong_grade = []
      not_found_or_unauthorized = []
      bulk_ops = []

      @learner_ids.each do |learner_id_str|
        lid_bson = BSON::ObjectId.legal?(learner_id_str) ? BSON::ObjectId.from_string(learner_id_str) : nil

        doc = Learner.collection.find("_id" => { "$in" => [learner_id_str, lid_bson].compact }).first

        if doc.nil?
          not_found_or_unauthorized << learner_id_str
          next
        end

        # 1. School isolation check
        doc_school_id = doc["school_id"].to_s
        if doc_school_id != resolved_school_id
          not_found_or_unauthorized << learner_id_str
          next
        end

        # 2. Duplicate promotion protection
        doc_grade_id = (doc["gradeId"] || doc["grade_id"]).to_s
        doc_current_year = (doc["current_academic_year"] || doc["academic_year"]).to_s
        history = doc["enrollment_history"] || doc["academic_history"] || []

        is_already_promoted = (
          doc_current_year == @destination_academic_year && doc_grade_id == destination_grade.id.to_s
        ) || history.any? do |h|
          h["academic_year"].to_s == @destination_academic_year ||
            h["destination_academic_year"].to_s == @destination_academic_year
        end

        if is_already_promoted
          already_promoted << learner_id_str
          next
        end

        # 3. Source grade check
        if doc_grade_id != source_grade.id.to_s
          wrong_grade << learner_id_str
          next
        end

        # 4. Eligible for promotion -> build snapshot and update
        snapshot = {
          "grade_id" => doc_grade_id,
          "grade_name" => source_grade.name,
          "academic_year" => doc_current_year.presence || @source_academic_year,
          "source_academic_year" => @source_academic_year,
          "destination_academic_year" => @destination_academic_year,
          "promoted_at" => Time.current.utc.iso8601,
          "promoted_by" => @user_id.to_s
        }

        bulk_ops << {
          update_one: {
            filter: { "_id" => doc["_id"] },
            update: {
              "$set" => {
                "gradeId" => destination_grade.id.to_s,
                "grade_id" => destination_grade.id.to_s,
                "current_academic_year" => @destination_academic_year.to_i,
                "academic_year" => @destination_academic_year,
                "school_class_id" => nil
              },
              "$push" => {
                "enrollment_history" => snapshot,
                "academic_history" => snapshot
              }
            }
          }
        }
        promoted << learner_id_str
      end

      # Execute bulk write if any eligible
      if bulk_ops.any?
        Learner.collection.bulk_write(bulk_ops, ordered: false)
      end

      promoted_count = promoted.size
      already_promoted_count = already_promoted.size
      wrong_grade_count = wrong_grade.size
      failed_count = not_found_or_unauthorized.size
      total_unsuccessful = already_promoted_count + wrong_grade_count + failed_count

      overall_success = total_unsuccessful.zero? && promoted_count > 0

      ServiceResult.new(
        success: overall_success,
        message: "Promotion completed. #{promoted_count} promoted, #{already_promoted_count} already promoted, #{wrong_grade_count} wrong grade, #{failed_count} failed.",
        summary: {
          promoted_count: promoted_count,
          already_promoted_count: already_promoted_count,
          wrong_grade_count: wrong_grade_count,
          failed_count: failed_count
        },
        promoted: promoted,
        already_promoted: already_promoted,
        wrong_grade: wrong_grade,
        not_found_or_unauthorized: not_found_or_unauthorized,
        errors: []
      )
    rescue => e
      Rails.logger.error "❌ [PromoteLearnersService] Error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      ServiceResult.new(
        success: false,
        message: "An unexpected error occurred during promotion: #{e.message}",
        summary: { promoted_count: 0, already_promoted_count: 0, wrong_grade_count: 0, failed_count: @learner_ids.size },
        promoted: [],
        already_promoted: [],
        wrong_grade: [],
        not_found_or_unauthorized: @learner_ids,
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
  end
end
