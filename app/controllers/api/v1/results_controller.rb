module Api
  module V1
    class ResultsController < Api::V1::BaseController
      before_action :set_school
      before_action :set_result, only: [:show, :update, :destroy]

      # GET /api/v1/results
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        assessment_id = raw_params[:assessment_id] || raw_params["assessment_id"] || raw_params[:assessmentId] || raw_params["assessmentId"]
        learner_id    = raw_params[:learner_id] || raw_params["learner_id"] || raw_params[:learnerId] || raw_params["learnerId"]

        scope = Result.all

        if assessment_id.present?
          begin
            assessment = Assessment.find(assessment_id)
            if assessment.school_id.to_s != @school.id.to_s
              return render json: { success: false, error: "Assessment does not belong to target school" }, status: :forbidden
            end
          rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
            return render json: { success: false, error: "Assessment not found" }, status: :not_found
          end
          scope = scope.by_assessment(assessment_id)
        else
          school_ass_ids = Assessment.by_school(@school.id.to_s).pluck(:_id).map(&:to_s)
          scope = scope.where(:assessment_id.in => school_ass_ids)
        end

        if learner_id.present?
          scope = scope.by_learner(learner_id)
        end

        results = scope.to_a

        render json: {
          success: true,
          total: results.size,
          results: results.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("ResultsController#index", e)
      end

      # GET /api/v1/results/:id
      def show
        render json: {
          success: true,
          result: @result.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/results
      def create
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        assessment_id = raw_payload[:assessment_id] || raw_payload["assessment_id"] || raw_payload[:assessmentId] || raw_payload["assessmentId"]
        learner_id = raw_payload[:learner_id] || raw_payload["learner_id"] || raw_payload[:learnerId] || raw_payload["learnerId"]
        score_val = raw_payload[:score]

        begin
          assessment = Assessment.find(assessment_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "Assessment not found" }, status: :not_found
        end

        if assessment.school_id.to_s != @school.id.to_s
          return render json: { success: false, error: "Assessment does not belong to target school" }, status: :forbidden
        end

        result_rec = Result.find_or_initialize_by(
          assessment_id: assessment.id.to_s,
          learner_id: learner_id.to_s
        )
        result_rec.score = score_val.to_f if score_val.present?

        if result_rec.save
          render json: {
            success: true,
            message: "Result recorded successfully",
            result: result_rec.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            errors: result_rec.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("ResultsController#create", e)
      end

      # PATCH/PUT /api/v1/results/:id
      def update
        score_val = params[:score]
        if score_val.present? && !@result.update(score: score_val.to_f)
          return render json: {
            success: false,
            errors: @result.errors.full_messages
          }, status: :unprocessable_entity
        end

        render json: {
          success: true,
          message: "Result updated successfully",
          result: @result.to_api_hash
        }, status: :ok
      rescue => e
        render_exception("ResultsController#update", e)
      end

      # DELETE /api/v1/results/:id
      def destroy
        if @result.destroy
          render json: {
            success: true,
            message: "Result deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @result.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/results/bulk_record
      def bulk_record
        raw_payload = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        assessment_id = raw_payload[:assessment_id] || raw_payload["assessment_id"] || raw_payload[:assessmentId] || raw_payload["assessmentId"]
        results_input = raw_payload[:results] || raw_payload["results"] || raw_payload[:records] || raw_payload["records"]

        if assessment_id.blank?
          return render json: { success: false, error: "assessment_id is required" }, status: :bad_request
        end

        unless results_input.is_a?(Array)
          return render json: { success: false, error: "results must be an array" }, status: :bad_request
        end

        begin
          assessment = Assessment.find(assessment_id)
        rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
          return render json: { success: false, error: "Assessment not found" }, status: :not_found
        end

        if assessment.school_id.to_s != @school.id.to_s
          return render json: { success: false, error: "Assessment does not belong to target school" }, status: :forbidden
        end

        saved_results = []
        errors = []

        results_input.each do |item|
          item_hash = item.is_a?(Hash) ? item.with_indifferent_access : {}
          learner_id = item_hash[:learner_id] || item_hash[:learnerId]
          score_val  = item_hash[:score]

          next if learner_id.blank? || score_val.nil?

          result_rec = Result.find_or_initialize_by(
            assessment_id: assessment.id.to_s,
            learner_id: learner_id.to_s
          )

          result_rec.score = score_val.to_f

          if result_rec.save
            saved_results << result_rec
          else
            errors << "Learner #{learner_id}: #{result_rec.errors.full_messages.join(', ')}"
          end
        end

        if errors.present? && saved_results.empty?
          return render json: { success: false, errors: errors }, status: :unprocessable_entity
        end

        render json: {
          success: true,
          recorded_count: saved_results.size,
          errors_count: errors.size,
          errors: errors.presence,
          results: saved_results.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("ResultsController#bulk_record", e)
      end

      # GET /api/v1/results/report_card?learner_id=&academic_year=&term=
      def report_card
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        learner_id    = raw_params[:learner_id] || raw_params["learner_id"] || raw_params[:learnerId] || raw_params["learnerId"]
        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        term_val      = raw_params[:term] || raw_params["term"]

        if learner_id.blank?
          return render json: { success: false, error: "learner_id is required" }, status: :bad_request
        end

        begin
          learner_doc = Learner.collection.find("_id" => { "$in" => [learner_id.to_s, (BSON::ObjectId.from_string(learner_id.to_s) rescue nil)].compact }).first
          unless learner_doc
            return render json: { success: false, error: "Learner not found" }, status: :not_found
          end
          learner = Learner.instantiate(learner_doc)
        rescue => e
          return render json: { success: false, error: "Learner not found" }, status: :not_found
        end

        ass_scope = Assessment.by_school(@school.id.to_s)
        ass_scope = ass_scope.by_academic_year(academic_year) if academic_year.present?
        ass_scope = ass_scope.by_term(term_val) if term_val.present?

        assessments = ass_scope.to_a
        ass_ids = assessments.map { |a| a.id.to_s }

        results = Result.where(:assessment_id.in => ass_ids, learner_id: learner_id.to_s).to_a
        results_by_ass_id = results.index_by { |r| r.assessment_id.to_s }

        subjects_data = {}

        assessments.each do |ass|
          sub_id = ass.subject_id.to_s
          sub_name = ass.subject_name || "Subject #{sub_id}"

          subjects_data[sub_id] ||= {
            subject_id: sub_id,
            subject_name: sub_name,
            assessments: [],
            total_earned: 0.0,
            total_possible: 0.0
          }

          res = results_by_ass_id[ass.id.to_s]
          if res
            subjects_data[sub_id][:assessments] << {
              assessment_id: ass.id.to_s,
              assessment_name: ass.name,
              score: res.score,
              max_score: ass.max_score,
              percentage: res.percentage
            }
            subjects_data[sub_id][:total_earned] += res.score.to_f
            subjects_data[sub_id][:total_possible] += ass.max_score.to_f
          else
            subjects_data[sub_id][:assessments] << {
              assessment_id: ass.id.to_s,
              assessment_name: ass.name,
              score: nil,
              max_score: ass.max_score,
              percentage: nil
            }
          end
        end

        subjects_summary = subjects_data.values.map do |sd|
          pct = sd[:total_possible] > 0 ? ((sd[:total_earned] / sd[:total_possible]) * 100).round(2) : nil
          {
            subject_id: sd[:subject_id],
            subject_name: sd[:subject_name],
            average_percentage: pct,
            assessments: sd[:assessments]
          }
        end

        overall_earned = subjects_data.values.sum { |s| s[:total_earned] }
        overall_possible = subjects_data.values.sum { |s| s[:total_possible] }
        overall_average = overall_possible > 0 ? ((overall_earned / overall_possible) * 100).round(2) : nil

        render json: {
          success: true,
          learner_id: learner_id.to_s,
          learner_name: learner.try(:full_name) || "#{learner_doc['first_name']} #{learner_doc['last_name']}".strip,
          academic_year: academic_year,
          term: term_val ? term_val.to_i : nil,
          overall_average_percentage: overall_average,
          subjects: subjects_summary
        }, status: :ok
      rescue => e
        render_exception("ResultsController#report_card", e)
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        if school_param.blank? && raw_params[:assessment_id].present?
          a = Assessment.find(raw_params[:assessment_id]) rescue nil
          school_param = a&.school_id
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

      def set_result
        @result = Result.find(params[:id])
        if @result.target_assessment&.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Result not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Result not found"
        }, status: :not_found and return
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
