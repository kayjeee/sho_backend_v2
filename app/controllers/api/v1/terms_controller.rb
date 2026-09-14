module Api
  module V1
    class TermsController < Api::V1::BaseController
      before_action :set_school
      before_action :set_term, only: [:show, :update, :destroy]

      # GET /api/v1/terms
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        scope = Term.by_school(@school.id.to_s)

        academic_year = raw_params[:academic_year] || raw_params["academic_year"] || raw_params[:academicYear] || raw_params["academicYear"]
        scope = scope.by_academic_year(academic_year) if academic_year.present?

        terms = scope.order(term_number: :asc).to_a

        render json: {
          success: true,
          total: terms.size,
          terms: terms.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("TermsController#index", e)
      end

      # GET /api/v1/terms/:id
      def show
        render json: {
          success: true,
          term: @term.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/terms
      def create
        term_data = term_params
        @term = Term.new(term_data)
        @term.school_id = @school.id.to_s

        if @term.save
          render json: {
            success: true,
            message: "Term created successfully",
            term: @term.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            error: @term.errors.full_messages.join(", "),
            errors: @term.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TermsController#create", e)
      end

      # PATCH/PUT /api/v1/terms/:id
      def update
        if @term.update(term_params)
          render json: {
            success: true,
            message: "Term updated successfully",
            term: @term.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            error: @term.errors.full_messages.join(", "),
            errors: @term.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("TermsController#update", e)
      end

      # DELETE /api/v1/terms/:id
      def destroy
        if @term.destroy
          render json: {
            success: true,
            message: "Term deleted successfully"
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @term.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/terms/current
      def current
        current_term = Term.current_for_school(@school.id.to_s)
        current_year = current_term ? current_term.academic_year : Date.current.year

        render json: {
          success: true,
          current_term: current_term ? current_term.to_api_hash : nil,
          current_academic_year: current_year
        }, status: :ok
      rescue => e
        render_exception("TermsController#current", e)
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        if school_param.blank? && raw_params[:term].is_a?(Hash)
          t_hash = raw_params[:term]
          school_param = t_hash[:school_id] || t_hash["school_id"] || t_hash[:schoolId] || t_hash["schoolId"]
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

      def set_term
        @term = Term.find(params[:id])
        if @term.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Term not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Term not found"
        }, status: :not_found and return
      end

      def term_params
        source = params[:term].presence || params
        source.permit(:school_id, :academic_year, :term_number, :name, :start_date, :end_date)
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
