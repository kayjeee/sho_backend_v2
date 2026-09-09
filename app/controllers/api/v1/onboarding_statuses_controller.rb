# app/controllers/api/v1/onboarding_statuses_controller.rb
module Api
  module V1
    class OnboardingStatusesController < ApplicationController
      include OnboardingAuthorization

      before_action :set_target_user
      before_action :set_request_context

      # GET /api/v1/users/:user_id/onboarding_status
      def show
        begin
          primary_school = UserServices::FetchSchoolsService.new(user: @target_user).call.first
          primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

          data = (@target_user.onboarding_status || {}).as_json
          data['onboarding_completed'] = @target_user.onboarding_completed
          data['onboardingCompleted'] = @target_user.onboarding_completed
          data['primary_school_name'] = primary_school_name
          data['primarySchoolName'] = primary_school_name
          data['school_name'] = primary_school_name
          data['schoolName'] = primary_school_name

          render json: {
            success: true,
            data: data,
            message: "Fetched onboarding status",
            metadata: @request_context
          }
        rescue StandardError => e
          Rails.logger.error "🔥 Error in show: #{e.message}"
          render json: { success: false, errors: [e.message], message: "Failed to fetch onboarding status" }, status: :internal_server_error
        end
      end

      # PATCH /api/v1/users/:user_id/onboarding_status
      def update
        begin
          updates = onboarding_params.to_h

          @target_user.ensure_onboarding_status
          @target_user.onboarding_status.assign_attributes_from_api(updates)

          # Recalculate metrics on the onboarding_status object explicitly
          @target_user.onboarding_status.calculate_progress_metrics
          @target_user.onboarding_status.auto_complete_if_ready!

          @target_user.save!

          # Return enriched data
          primary_school = UserServices::FetchSchoolsService.new(user: @target_user).call.first
          primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

          data = @target_user.onboarding_status.as_json
          data['onboarding_completed'] = @target_user.onboarding_completed
          data['onboardingCompleted'] = @target_user.onboarding_completed
          data['primary_school_name'] = primary_school_name
          data['primarySchoolName'] = primary_school_name
          data['school_name'] = primary_school_name
          data['schoolName'] = primary_school_name

          render json: {
            success: true,
            data: data,
            message: "Onboarding status updated",
            metadata: @request_context
          }
        rescue StandardError => e
          Rails.logger.error "🔥 Error in update: #{e.message}"
          render json: { success: false, errors: [e.message], message: "Failed to update onboarding status" }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/complete_step
      def complete_step
        begin
          step_name = params[:step_name] || params[:stepName]
          step_metadata = params[:metadata] || params[:metaData] || {}

          # Delegate to service
          result = OnboardingStatusService.complete_step(
            @target_user,
            step_name,
            step_metadata,
            @request_context
          )

          if result[:success]
            primary_school = UserServices::FetchSchoolsService.new(user: @target_user).call.first
            primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

            data = @target_user.reload.onboarding_status.as_json
            data['onboarding_completed'] = @target_user.onboarding_completed
            data['onboardingCompleted'] = @target_user.onboarding_completed
            data['primary_school_name'] = primary_school_name
            data['primarySchoolName'] = primary_school_name
            data['school_name'] = primary_school_name
            data['schoolName'] = primary_school_name

            render json: {
              success: true,
              message: result[:message],
              data: data,
              metadata: @request_context
            }
          else
            render json: {
              success: false,
              errors: result[:errors],
              message: result[:message]
            }, status: :bad_request
          end
        rescue StandardError => e
          Rails.logger.error "🔥 Error in complete_step: #{e.message}"
          render json: { success: false, errors: [e.message], message: "Failed to complete step" }, status: :internal_server_error
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/skip_step
      def skip_step
        begin
          step_name = params[:step_name] || params[:stepName]
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

          @target_user.ensure_onboarding_status
          @target_user.onboarding_status.skip_step!(step_name, reason: reason)

          @target_user.onboarding_status.calculate_progress_metrics
          @target_user.onboarding_status.save!

          primary_school = UserServices::FetchSchoolsService.new(user: @target_user).call.first
          primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

          data = @target_user.reload.onboarding_status.as_json
          data['onboarding_completed'] = @target_user.onboarding_completed
          data['onboardingCompleted'] = @target_user.onboarding_completed
          data['primary_school_name'] = primary_school_name
          data['primarySchoolName'] = primary_school_name
          data['school_name'] = primary_school_name
          data['schoolName'] = primary_school_name

          render json: {
            success: true,
            data: data,
            message: "Step '#{step_name}' skipped",
            metadata: @request_context
          }
        rescue StandardError => e
          Rails.logger.error "🔥 Error in skip_step: #{e.message}"
          render json: { success: false, errors: [e.message], message: "Failed to skip step" }, status: :internal_server_error
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/reset
      def reset
        begin
          reset_reason = params[:reason] || "API reset request"

          @target_user.ensure_onboarding_status
          @target_user.onboarding_status.reset!

          @target_user.onboarding_completed = false if @target_user.respond_to?(:onboarding_completed=)
          @target_user.onboarding_progress = 0.0 if @target_user.respond_to?(:onboarding_progress=)
          @target_user.set(onboarding_completed: false, onboarding_progress: 0.0)

          primary_school = UserServices::FetchSchoolsService.new(user: @target_user).call.first
          primary_school_name = primary_school&.schoolName || primary_school&.[](:schoolName)

          data = @target_user.reload.onboarding_status.as_json
          data['onboarding_completed'] = @target_user.onboarding_completed
          data['onboardingCompleted'] = @target_user.onboarding_completed
          data['primary_school_name'] = primary_school_name
          data['primarySchoolName'] = primary_school_name
          data['school_name'] = primary_school_name
          data['schoolName'] = primary_school_name

          render json: {
            success: true,
            data: data,
            message: "Onboarding reset",
            metadata: @request_context.merge("reset_reason" => reset_reason)
          }
        rescue StandardError => e
          Rails.logger.error "🔥 Error in reset: #{e.message}"
          render json: { success: false, errors: [e.message], message: "Failed to reset onboarding" }, status: :internal_server_error
        end
      end

      private

      def set_target_user
        # Account for routing schema update where parent ID is params[:user_auth0_id]
        target_id = params[:user_auth0_id] || params[:auth0_id] || params[:user_id] || params[:id]

        if target_id.blank?
          if request.headers['Authorization'].present?
            begin
              authorize
              if @decoded_token && @decoded_token.respond_to?(:token) && @decoded_token.token.is_a?(Array)
                target_id = @decoded_token.token[0]['sub']
              end
            rescue => e
              Rails.logger.error "⚠️ Could not authorize token in fallback set_target_user: #{e.message}"
            end
          end
        end

        if target_id.blank?
          render json: { success: false, error: "User not found", message: "User identifier is required" }, status: :not_found
          return
        end

        @target_user =
          if target_id.to_s.include?('|') || !target_id.to_s.match?(/^[a-f\d]{24}$/i)
            # Safe lookup by auth0_id for strings containing pipes or non-hex patterns
            User.find_by(auth0_id: target_id)
          else
            # Standard BSON ID lookup
            if BSON::ObjectId.legal?(target_id)
              User.find(target_id)
            else
              nil
            end
          end

        render(json: { success: false, message: "User not found" }, status: :not_found) unless @target_user
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
        render json: { success: false, message: "User not found" }, status: :not_found
      rescue StandardError => e
        Rails.logger.error "🔥 Unexpected error in set_target_user: #{e.message}"
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

      def requires_skip_reason?(step_name)
        # Define which steps require a skip reason
        ["create_grades", "upload_learners", "send_invites"].include?(step_name.to_s.underscore)
      end
    end
  end
end
