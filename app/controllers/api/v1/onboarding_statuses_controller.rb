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

      # GET /api/v1/users/:user_id/onboarding_statuses
      def show
        render json: {
          success: true,
          data: @target_user.onboarding_status || {},
          message: "Fetched onboarding status",
          metadata: @request_context
        }
      end

      # PATCH /api/v1/users/:user_id/onboarding_statuses
      def update
        updates = onboarding_params.to_h.deep_transform_keys { |k| k.to_s.underscore }

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

      # POST /api/v1/users/:user_id/onboarding_statuses/complete_step
      def complete_step
        step_name     = params[:step_name].to_s.underscore
        step_metadata = params[:metadata] || {}

        if step_name.blank?
          return render json: {
            success: false,
            errors: ["Step name is required"],
            message: "Missing step name parameter"
          }, status: :bad_request
        end

        metadata_hash =
          if step_metadata.respond_to?(:to_unsafe_hash)
            step_metadata.to_unsafe_hash
          else
            step_metadata.to_h
          end

        result = OnboardingStatusService.complete_step(
          @target_user,
          step_name,
          metadata_hash.deep_transform_keys(&:underscore),
          @request_context
        )

        if result[:success]
          render json: {
            success: true,
            message: "Step '#{step_name}' completed",
            data: result[:data],
            metadata: @request_context
          }
        else
          render json: {
            success: false,
            message: "Failed to complete step",
            errors: [result[:error]]
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_statuses/skip_step
      def skip_step
        step_name = params[:step_name].to_s.underscore
        reason    = params[:reason]

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

        skipped = { step: step_name, reason: reason, skipped_at: Time.current.iso8601 }

        @target_user.push("onboarding_status.skipped_steps" => skipped)

        render json: {
          success: true,
          data: @target_user.reload.onboarding_status,
          message: "Step '#{step_name}' skipped"
        }
      end

      # POST /api/v1/users/:user_id/onboarding_statuses/reset
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
