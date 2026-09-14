module Api
  module V1
    class AttendanceController < Api::V1::BaseController
      before_action :set_school, only: [:bulk_mark, :register, :summary]

      # POST /api/v1/attendance/bulk_mark
      def bulk_mark
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        class_id = raw_payload[:school_class_id] || raw_payload["school_class_id"] || raw_payload[:schoolClassId] || raw_payload["schoolClassId"]
        date_str = raw_payload[:date] || raw_payload["date"]
        records_input = raw_payload[:records] || raw_payload["records"]
        recorded_by = raw_payload[:recorded_by_id] || raw_payload["recorded_by_id"] || raw_payload[:user_id] || raw_payload["user_id"] || "system"

        if class_id.blank?
          return render json: { success: false, error: "school_class_id is required" }, status: :bad_request
        end

        if date_str.blank?
          return render json: { success: false, error: "date is required" }, status: :bad_request
        end

        unless records_input.is_a?(Array)
          return render json: { success: false, error: "records must be an array" }, status: :bad_request
        end

        begin
          school_class = SchoolClass.find(class_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "School class not found" }, status: :not_found
        end

        grade = school_class.grade
        unless grade
          return render json: { success: false, error: "Grade association missing for school class" }, status: :unprocessable_entity
        end

        # Server-side verification of school ownership
        if school_class.grade.school_id.to_s != @school.id.to_s
          return render json: { success: false, error: "School class does not belong to target school" }, status: :forbidden
        end

        target_date = Date.parse(date_str.to_s) rescue nil
        unless target_date
          return render json: { success: false, error: "Invalid date format" }, status: :bad_request
        end

        saved_records = []

        records_input.each do |rec|
          rec_hash = rec.is_a?(Hash) ? rec.with_indifferent_access : {}
          learner_id = rec_hash[:learner_id] || rec_hash[:learnerId]
          next if learner_id.blank?

          status_val = parse_status(rec_hash[:status])
          next if status_val.nil?

          att_record = AttendanceRecord.find_or_initialize_by(
            school_class_id: school_class.id.to_s,
            learner_id: learner_id.to_s,
            date: target_date
          )

          att_record.school_id = @school.id.to_s
          att_record.grade_id = grade.id.to_s
          att_record.status = status_val
          att_record.note = rec_hash[:note] if rec_hash.key?(:note)
          att_record.recorded_by_id = recorded_by.to_s

          if att_record.save
            saved_records << att_record
          else
            Rails.logger.warn "⚠️ Failed to save AttendanceRecord for learner #{learner_id}: #{att_record.errors.full_messages.join(', ')}"
          end
        end

        render json: {
          success: true,
          marked_count: saved_records.size,
          records: saved_records.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("AttendanceController#bulk_mark", e)
      end

      # GET /api/v1/attendance/register?school_class_id=&date=
      def register
        class_id = params[:school_class_id] || params[:schoolClassId]
        date_str = params[:date]

        if class_id.blank?
          return render json: { success: false, error: "school_class_id is required" }, status: :bad_request
        end

        if date_str.blank?
          return render json: { success: false, error: "date is required" }, status: :bad_request
        end

        begin
          school_class = SchoolClass.find(class_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "School class not found" }, status: :not_found
        end

        grade = school_class.grade

        if school_class.grade.school_id.to_s != @school.id.to_s
          return render json: { success: false, error: "School class does not belong to target school" }, status: :forbidden
        end

        target_date = Date.parse(date_str.to_s) rescue nil
        unless target_date
          return render json: { success: false, error: "Invalid date format" }, status: :bad_request
        end

        # Find existing attendance records for class and date
        existing_records = AttendanceRecord.where(
          school_class_id: school_class.id.to_s,
          date: target_date
        ).index_by { |r| r.learner_id.to_s }

        # Fetch learners in class roster
        raw_learner_ids = Array(school_class.learner_ids).map(&:to_s)
        learner_bsons = raw_learner_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact

        learners_docs = Learner.collection.find(
          "_id" => { "$in" => (raw_learner_ids + learner_bsons).uniq }
        ).to_a

        learners_map = learners_docs.each_with_object({}) do |doc, hash|
          learner = Learner.instantiate(doc)
          full_name = learner.try(:full_name) || "#{doc['first_name'] || doc['firstName']} #{doc['last_name'] || doc['lastName']}".strip
          hash[doc["_id"].to_s] = full_name
        end

        roster = raw_learner_ids.map do |lid|
          record = existing_records[lid]
          {
            learner_id: lid,
            learner_name: learners_map[lid] || "Learner #{lid}",
            status: record ? record.status_text : "unmarked",
            status_code: record ? record.status : nil,
            note: record&.note,
            recorded_by_id: record&.recorded_by_id
          }
        end

        render json: {
          success: true,
          class_name: school_class.name,
          grade_name: grade&.name,
          date: target_date.iso8601,
          roster: roster
        }, status: :ok
      rescue => e
        render_exception("AttendanceController#register", e)
      end

      # GET /api/v1/attendance/summary?school_id=&from=&to=&learner_id=
      def summary
        from_date = params[:from].present? ? (Date.parse(params[:from].to_s) rescue nil) : nil
        to_date   = params[:to].present?   ? (Date.parse(params[:to].to_s) rescue nil)   : nil
        learner_id = params[:learner_id] || params[:learnerId]

        scope = AttendanceRecord.by_school(@school.id.to_s)
        scope = scope.by_date_range(from_date, to_date) if from_date || to_date
        scope = scope.by_learner(learner_id) if learner_id.present?

        records = scope.to_a

        by_status = {
          "present" => records.count { |r| r.status == 0 },
          "absent"  => records.count { |r| r.status == 1 },
          "late"    => records.count { |r| r.status == 2 },
          "excused" => records.count { |r| r.status == 3 }
        }

        render json: {
          success: true,
          school_id: @school.id.to_s,
          learner_id: learner_id,
          from: from_date&.iso8601,
          to: to_date&.iso8601,
          total_records: records.size,
          summary: by_status
        }, status: :ok
      rescue => e
        render_exception("AttendanceController#summary", e)
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        # If school_id is missing, infer school from school_class_id
        if school_param.blank?
          class_id = raw_params[:school_class_id] || raw_params["school_class_id"] || raw_params[:schoolClassId] || raw_params["schoolClassId"]
          if class_id.present?
            sc = SchoolClass.find(class_id) rescue nil
            school_param = sc&.grade&.school_id if sc&.grade
          end
        end

        if school_param.blank?
          render json: {
            success: false,
            error: "School context identifier is required."
          }, status: :bad_request and return
        end

        @school = find_school_by_id_or_slug(school_param)
        unless @school
          render json: {
            success: false,
            error: "School not found"
          }, status: :not_found and return
        end
      rescue AmbiguousSchoolError => e
        render json: {
          success: false,
          error: e.message,
          matching_schools: e.matching_schools.map { |s| { id: s.id.to_s, name: s.schoolName } }
        }, status: :conflict and return
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "School not found"
        }, status: :not_found and return
      end

      def parse_status(val)
        return nil if val.nil?

        if val.is_a?(Numeric) || val.to_s.match?(/\A\d+\z/)
          i = val.to_i
          return AttendanceRecord::STATUSES.values.include?(i) ? i : nil
        end

        AttendanceRecord::STATUSES[val.to_s.downcase]
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
