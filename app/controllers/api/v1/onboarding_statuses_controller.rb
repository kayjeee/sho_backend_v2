# app/controllers/api/v1/onboarding_statuses_controller.rb
module Api
  module V1
    class OnboardingStatusesController < ApplicationController
      include OnboardingAuthorization

      before_action :set_target_user
      before_action :set_request_context

      # -----------------------------
      # Actions
      # -----------------------------

      # GET /api/v1/users/:user_id/onboarding_status
      def show
        render json: {
          success: true,
          data: @target_user.onboarding_status || {},
          message: "Fetched onboarding status",
          metadata: @request_context
        }
      end

      # PATCH /api/v1/users/:user_id/onboarding_status
      def update
        updates = onboarding_params.to_h

        updates.each do |key, value|
          @target_user.set("onboarding_status.#{key}" => value)
        end

        # Add request metadata
        @target_user.set(
          "onboarding_status._request_metadata" => {
            "updated_at" => Time.current.iso8601,
            "user_agent" => request.user_agent,
            "ip_address" => request.remote_ip
          }
        )

        render json: {
          success: true,
          data: @target_user.reload.onboarding_status,
          message: "Onboarding status updated",
          metadata: @request_context
        }
      end

      # POST /api/v1/users/:user_id/onboarding_status/complete_step
      def complete_step
        step_name = params[:step_name]
        step_metadata = params[:metadata] || {}

        if step_name.blank?
          return render json: { success: false, errors: ["Step name is required"], message: "Missing step name parameter" },
                        status: :bad_request
        end

        metadata_hash = step_metadata.respond_to?(:to_unsafe_hash) ? step_metadata.to_unsafe_hash : step_metadata.to_h

        validation_result = validate_step_metadata(step_name, metadata_hash)
        unless validation_result[:valid]
          return render json: { success: false, errors: validation_result[:errors], message: "Invalid step metadata" },
                        status: :bad_request
        end

        # Safe metadata
        safe_metadata = {}
        safe_metadata["grades"]   = Array.wrap(metadata_hash["grades"]).compact if metadata_hash["grades"].present?
        safe_metadata["schoolId"] = metadata_hash["schoolId"] if metadata_hash["schoolId"].present?

        enriched_metadata = safe_metadata.merge(
          "request_id" => request.uuid,
          "user_agent" => request.user_agent,
          "ip_address" => request.remote_ip
        )

        begin
          # atomic $set update for step
          @target_user.set("onboarding_status.#{step_name}" => enriched_metadata)

          # optional side-effect
          create_grades_from_metadata(@target_user, safe_metadata) if step_name.to_s == "create_grades"

          render json: {
            success: true,
            message: "Step '#{step_name}' completed",
            data: enriched_metadata,
            metadata: @request_context
          }
        rescue => e
          Rails.logger.error "🔥 Error completing step: #{e.message}\n#{e.backtrace.join("\n")}"
          render json: { success: false, message: "Unexpected error", errors: [e.message] }, status: :internal_server_error
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/skip_step
      def skip_step
        step_name = params[:step_name]
        reason    = params[:reason]

        if step_name.blank?
          return render json: { success: false, errors: ["Step name is required"], message: "Missing step name parameter" },
                        status: :bad_request
        end

        if requires_skip_reason?(step_name) && reason.blank?
          return render json: { success: false, errors: ["Skip reason is required for this step"], message: "Missing skip reason" },
                        status: :bad_request
        end

        skipped = { step: step_name, reason: reason, skipped_at: Time.current.iso8601 }

        # atomic $push to skipped_steps array
        @target_user.push("onboarding_status.skipped_steps" => skipped)

        render json: {
          success: true,
          data: @target_user.reload.onboarding_status,
          message: "Step '#{step_name}' skipped"
        }
      end

      # POST /api/v1/users/:user_id/onboarding_status/reset
      def reset
        reset_reason = params[:reason] || "API reset request"

        @target_user.set(onboarding_status: {})

        render json: {
          success: true,
          data: {},
          message: "Onboarding reset",
          metadata: @request_context.merge("reset_reason" => reset_reason)
        }
      end

      private

      # -------------------------------------
      # Inline grade creation side-effect
      # -------------------------------------
      def create_grades_from_metadata(user, metadata)
        grades    = Array.wrap(metadata["grades"]).compact
        school_id = metadata["schoolId"]

        return unless grades.any? && school_id.present?

        current_year        = Date.current.year
        academic_year_start = Date.new(current_year, 1, 1)
        academic_year_end   = Date.new(current_year, 12, 31)

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
          rescue => e
            Rails.logger.error "🔥 Error creating grade '#{grade_name}' for school #{school_id}: #{e.message}"
          end
        end
      end

      def set_target_user
        user_id = params[:user_id] || params[:id]
        @target_user =
          if user_id.match?(/^[a-f\d]{24}$/i)
            User.find(user_id)
          else
            User.find_by(auth0_id: user_id)
          end

        render(json: { success: false, message: "User not found" }, status: :not_found) unless @target_user
      rescue Mongoid::Errors::DocumentNotFound, BSON::ObjectId::Invalid
        render json: { success: false, message: "User not found" }, status: :not_found
      end

      def set_request_context
        @request_context = {
          request_id: request.uuid,
          user_agent: request.user_agent,
          ip_address: request.remote_ip,
          target_user_id: @target_user&.auth0_id,
          timestamp: Time.current.iso8601,
          endpoint: "#{request.method} #{request.path}"
        }
      end

      def onboarding_params
        params.permit(
          :createGrades,
          :uploadLearners,
          :sendInvites,
          :adminOnboardingCompleted,
          :parentOnboardingCompleted,
          :guestOnboardingCompleted,
          :currentStep,
          skippedSteps: []
        )
      end
    end
  end
end
