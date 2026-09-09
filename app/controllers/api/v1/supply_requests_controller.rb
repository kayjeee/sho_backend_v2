module Api
  module V1
    class SupplyRequestsController < Api::V1::BaseController
      before_action :set_school
      before_action :set_supply_request, only: [:approve, :reject, :fulfill]

      # GET /api/v1/supply_requests
      def index
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        scope = SupplyRequest.by_school(@school.id.to_s)

        teacher_id = raw_params[:teacher_id] || raw_params["teacher_id"] || raw_params[:teacherId] || raw_params["teacherId"]
        status_param = raw_params[:status] || raw_params["status"]

        scope = scope.by_teacher(teacher_id) if teacher_id.present?

        if status_param.present?
          if status_param.to_s.match?(/\A\d+\z/)
            scope = scope.where(status: status_param.to_i)
          else
            s_val = SupplyRequest::STATUSES[status_param.to_s.downcase]
            scope = scope.where(status: s_val) if s_val.present?
          end
        end

        requests = scope.order(requested_at: :desc).to_a

        render json: {
          success: true,
          total: requests.size,
          supply_requests: requests.map(&:to_api_hash)
        }, status: :ok
      rescue => e
        render_exception("SupplyRequestsController#index", e)
      end

      # POST /api/v1/supply_requests
      def create
        req_data = supply_request_params
        @supply_request = SupplyRequest.new(req_data)
        @supply_request.school_id = @school.id.to_s

        if @supply_request.save
          render json: {
            success: true,
            message: "Supply request created successfully",
            supply_request: @supply_request.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            errors: @supply_request.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue => e
        render_exception("SupplyRequestsController#create", e)
      end

      # PATCH /api/v1/supply_requests/:id/approve
      def approve
        reviewer_id = params[:reviewer_id] || params[:reviewerId] || params[:user_id] || "admin"
        note = params[:admin_note] || params[:adminNote] || params[:note]

        if @supply_request.approve!(reviewer_id, note)
          render json: {
            success: true,
            message: "Supply request approved successfully",
            supply_request: @supply_request.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @supply_request.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/supply_requests/:id/reject
      def reject
        reviewer_id = params[:reviewer_id] || params[:reviewerId] || params[:user_id] || "admin"
        note = params[:admin_note] || params[:adminNote] || params[:note]

        if @supply_request.reject!(reviewer_id, note)
          render json: {
            success: true,
            message: "Supply request rejected successfully",
            supply_request: @supply_request.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @supply_request.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/supply_requests/:id/fulfill
      def fulfill
        reviewer_id = params[:reviewer_id] || params[:reviewerId] || params[:user_id]
        note = params[:admin_note] || params[:adminNote] || params[:note]

        if @supply_request.fulfill!(reviewer_id, note)
          render json: {
            success: true,
            message: "Supply request fulfilled successfully",
            supply_request: @supply_request.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @supply_request.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/supply_requests/summary
      def summary
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        teacher_id = raw_params[:teacher_id] || raw_params["teacher_id"] || raw_params[:teacherId] || raw_params["teacherId"]

        scope = SupplyRequest.by_school(@school.id.to_s)
        scope = scope.by_teacher(teacher_id) if teacher_id.present?

        all_reqs = scope.to_a

        if teacher_id.present?
          summary_data = {
            teacher_id: teacher_id.to_s,
            total_requests: all_reqs.size,
            requested_quantity: all_reqs.sum(&:quantity),
            approved_quantity: all_reqs.select { |r| r.status == 1 }.sum(&:quantity),
            fulfilled_quantity: all_reqs.select { |r| r.status == 3 }.sum(&:quantity),
            rejected_quantity: all_reqs.select { |r| r.status == 2 }.sum(&:quantity)
          }
        else
          grouped = all_reqs.group_by(&:teacher_id)
          summary_data = grouped.map do |tid, reqs|
            {
              teacher_id: tid.to_s,
              teacher_name: reqs.first&.teacher_name,
              total_requests: reqs.size,
              requested_quantity: reqs.sum(&:quantity),
              approved_quantity: reqs.select { |r| r.status == 1 }.sum(&:quantity),
              fulfilled_quantity: reqs.select { |r| r.status == 3 }.sum(&:quantity),
              rejected_quantity: reqs.select { |r| r.status == 2 }.sum(&:quantity)
            }
          end
        end

        render json: {
          success: true,
          school_id: @school.id.to_s,
          summary: summary_data
        }, status: :ok
      rescue => e
        render_exception("SupplyRequestsController#summary", e)
      end

      private

      def set_school
        raw_params = begin
          params.to_unsafe_h
        rescue
          params.to_h
        end

        school_param = raw_params[:school_id] || raw_params["school_id"] || raw_params[:schoolId] || raw_params["schoolId"]

        if school_param.blank? && raw_params[:supply_request].is_a?(Hash)
          s_hash = raw_params[:supply_request]
          school_param = s_hash[:school_id] || s_hash["school_id"] || s_hash[:schoolId] || s_hash["schoolId"]
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

      def set_supply_request
        @supply_request = SupplyRequest.find(params[:id])
        if @supply_request.school_id.to_s != @school.id.to_s
          render json: {
            success: false,
            error: "Supply request not found"
          }, status: :not_found and return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId
        render json: {
          success: false,
          error: "Supply request not found"
        }, status: :not_found and return
      end

      def supply_request_params
        source = params[:supply_request].presence || params
        source.permit(:school_id, :teacher_id, :item_type, :quantity, :unit, :reason, :admin_note)
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end
