module Api
  module V1
    class OnboardingStatusesController < ApplicationController
      include OnboardingAuthorization

      before_action :set_target_user
      before_action :set_request_context
      # before_action :check_rate_limit, only: [:update, :complete_step, :skip_step, :reset]

      # -----------------------------
      # Actions
      # -----------------------------

      # GET /api/v1/users/:user_id/onboarding_status
      def show
        result = UserServices::OnboardingStatusService.get_status(
          user: @target_user,
          context: @request_context
        )
        render json: result_response(result)
      end

      # PATCH /api/v1/users/:user_id/onboarding_status
      def update
        updates = onboarding_params.to_h

        updates_with_context = updates.merge(
          "_request_metadata" => {
            "updated_at" => Time.current.iso8601,
            "user_agent" => request.user_agent,
            "ip_address" => request.remote_ip
          }
        )

        result = UserServices::OnboardingStatusService.update_status(
          user: @target_user,
          updates: updates_with_context,
          context: @request_context
        )
        render json: result_response(result)
      end

      # POST /api/v1/users/:user_id/onboarding_status/complete_step
      def complete_step
        step_name = params[:step_name]
        step_metadata = params[:metadata] || {}

        if step_name.blank?
          return render json: {
            success: false,
            errors: ["Step name is required"],
            message: "Missing step name parameter"
          }, status: :bad_request
        end

        # Convert metadata to hash for validation
        metadata_hash = step_metadata.to_unsafe_hash if step_metadata.respond_to?(:to_unsafe_hash)
        metadata_hash ||= step_metadata.to_h

        # Validate metadata using the OnboardingAuthorization concern
        validation_result = validate_step_metadata(step_name, metadata_hash)
        unless validation_result[:valid]
          return render json: {
            success: false,
            errors: validation_result[:errors],
            message: "Invalid step metadata"
          }, status: :bad_request
        end

        # Convert metadata to a hash to prevent BSON serialization errors
        enriched_metadata = metadata_hash.merge(
          "request_id" => request.uuid,
          "user_agent" => request.user_agent,
          "ip_address" => request.remote_ip
        )

        result = UserServices::OnboardingStatusService.complete_step(
          user: @target_user,
          step_name: step_name,
          metadata: enriched_metadata,
          context: @request_context
        )

        render json: result_response(result)
      end

      # POST /api/v1/users/:user_id/onboarding_status/skip_step
      def skip_step
        step_name = params[:step_name]
        reason = params[:reason]

        if step_name.blank?
          return render json: {
            success: false,
            errors: ["Step name is required"],
            message: "Missing step name parameter"
          }, status: :bad_request
        end

        if requires_skip_reason?(step_name) && reason.blank?
          return render json: {
            success: false,
            errors: ["Skip reason is required for this step"],
            message: "Missing skip reason"
          }, status: :bad_request
        end

        result = UserServices::OnboardingStatusService.skip_step(
          user: @target_user,
          step_name: step_name,
          reason: reason,
          context: @request_context.merge("request_id" => request.uuid)
        )
        render json: result_response(result)
      end

      # POST /api/v1/users/:user_id/onboarding_status/reset
      def reset
        reset_reason = params[:reason] || "API reset request"

        result = UserServices::OnboardingStatusService.reset_onboarding(
          user: @target_user,
          reset_by: "system",
          reason: reset_reason,
          context: @request_context.merge(
            "reset_method" => "api_reset",
            "request_id" => request.uuid
          )
        )
        render json: result_response(result)
      end

      private

      # -----------------------------
      # Helpers
      # -----------------------------
      def set_target_user
        user_id = params[:user_id] || params[:id]
        @target_user =
          if user_id.match?(/^[a-f\d]{24}$/i)
            User.find(user_id)
          else
            User.find_by(auth0_id: user_id)
          end

        unless @target_user
          render json: { success: false, message: "User not found" }, status: :not_found
        end
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

      def result_response(result)
        if result.success?
          { success: true, data: result.data, message: result.message, metadata: result.metadata }
        else
          { success: false, errors: result.errors, message: result.message }
        end
      end
    end
  end
end