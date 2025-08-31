# app/controllers/api/v1/onboarding_status_controller.rb
module Api
  module V1
    class OnboardingStatusController < ApplicationController
      include OnboardingAuthorization
      
      before_action :authenticate_user!
      before_action :set_target_user
      before_action :authorize_onboarding_access!
      before_action :set_request_context
      
      # Rate limiting for API endpoints
      before_action :check_rate_limit, only: [:update, :complete_step, :skip_step, :complete, :reset]
      
      # Logging and monitoring
      around_action :log_request_performance
      after_action :track_api_usage

      # GET /api/v1/users/:user_id/onboarding_status
      def show
        Rails.logger.debug "📊 OnboardingStatusController#show: Getting status for user #{@target_user.auth0_id}"
        
        result = UserServices::OnboardingStatusService.get_status(
          user: @target_user,
          context: @request_context
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/users/:user_id/onboarding_status
      def update
        Rails.logger.debug "🔄 OnboardingStatusController#update: Updating status for user #{@target_user.auth0_id}"
        
        updates = onboarding_params.to_h
        
        # Add request metadata to updates
        updates_with_context = updates.merge(
          '_request_metadata' => {
            'updated_by' => current_user.auth0_id,
            'updated_at' => Time.current.iso8601,
            'user_agent' => request.user_agent,
            'ip_address' => request.remote_ip
          }
        )
        
        result = UserServices::OnboardingStatusService.update_status(
          user: @target_user,
          updates: updates_with_context,
          context: @request_context
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/complete_step
      def complete_step
        step_name = params[:step_name]
        step_metadata = params[:metadata] || {}
        
        Rails.logger.debug "✅ OnboardingStatusController#complete_step: Completing step '#{step_name}' for user #{@target_user.auth0_id}"
        
        if step_name.blank?
          return render json: {
            success: false,
            errors: ["Step name is required"],
            message: "Missing step name parameter"
          }, status: :bad_request
        end
        
        # Validate step metadata
        validation_result = validate_step_metadata(step_name, step_metadata)
        unless validation_result[:valid]
          return render json: {
            success: false,
            errors: validation_result[:errors],
            message: "Invalid step metadata"
          }, status: :bad_request
        end
        
        # Add request context to metadata
        enriched_metadata = step_metadata.merge(
          'completed_by' => current_user.auth0_id,
          'request_id' => request.uuid,
          'user_agent' => request.user_agent,
          'ip_address' => request.remote_ip
        )
        
        result = UserServices::OnboardingStatusService.complete_step(
          user: @target_user,
          step_name: step_name,
          metadata: enriched_metadata,
          context: @request_context
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/skip_step
      def skip_step
        step_name = params[:step_name]
        reason = params[:reason]
        
        Rails.logger.debug "⏭️ OnboardingStatusController#skip_step: Skipping step '#{step_name}' for user #{@target_user.auth0_id}"
        
        if step_name.blank?
          return render json: {
            success: false,
            errors: ["Step name is required"],
            message: "Missing step name parameter"
          }, status: :bad_request
        end
        
        # Validate skip reason for certain steps
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
          context: @request_context.merge(
            'skipped_by' => current_user.auth0_id,
            'request_id' => request.uuid
          )
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/complete
      def complete
        Rails.logger.debug "🏁 OnboardingStatusController#complete: Completing onboarding for user #{@target_user.auth0_id}"
        
        # Only allow admins or the user themselves to force complete onboarding
        unless can_force_complete_onboarding?
          return render json: {
            success: false,
            message: "Unauthorized to force complete onboarding"
          }, status: :forbidden
        end
        
        result = UserServices::OnboardingStatusService.complete_onboarding(
          user: @target_user,
          context: @request_context.merge(
            'force_completed_by' => current_user.auth0_id,
            'completion_method' => 'api_force_complete'
          )
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:user_id/onboarding_status/reset
      def reset
        Rails.logger.debug "🔄 OnboardingStatusController#reset: Resetting onboarding for user #{@target_user.auth0_id}"
        
        # Only allow admins or the user themselves to reset onboarding
        unless can_reset_onboarding?
          return render json: {
            success: false,
            message: "Unauthorized to reset onboarding status"
          }, status: :forbidden
        end
        
        reset_reason = params[:reason] || 'API reset request'
        
        result = UserServices::OnboardingStatusService.reset_onboarding(
          user: @target_user,
          reset_by: current_user.auth0_id,
          reason: reset_reason,
          context: @request_context.merge(
            'reset_method' => 'api_reset',
            'request_id' => request.uuid
          )
        )
        
        if result.success?
          render json: {
            success: true,
            data: result.data,
            message: result.message,
            metadata: result.metadata
          }, status: :ok
        else
          render json: {
            success: false,
            errors: result.errors,
            message: result.message
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/users/:user_id/onboarding_status/next_step
      def next_step
        Rails.logger.debug "🎯 OnboardingStatusController#next_step: Getting next step for user #{@target_user.auth0_id}"
        
        @target_user.ensure_onboarding_status
        onboarding_status = @target_user.onboarding_status
        
        next_step_info = {
          nextStep: onboarding_status.next_step,
          currentStep: onboarding_status.current_step,
          completed: onboarding_status.completed,
          canSkip: can_skip_current_step?(onboarding_status.current_step),
          estimatedTimeMinutes: estimate_step_time(onboarding_status.next_step),
          stepDescription: get_step_description(onboarding_status.next_step),
          prerequisites: get_step_prerequisites(onboarding_status.next_step)
        }
        
        render json: {
          success: true,
          data: next_step_info,
          message: "Next step information retrieved successfully"
        }, status: :ok
      end

      # GET /api/v1/users/:user_id/onboarding_status/analytics
      def analytics
        Rails.logger.debug "📊 OnboardingStatusController#analytics: Getting analytics for user #{@target_user.auth0_id}"
        
        # Only allow admins or the user themselves to view analytics
        unless can_view_analytics?
          return render json: {
            success: false,
            message: "Unauthorized to view onboarding analytics"
          }, status: :forbidden
        end
        
        analytics_data = @target_user.onboarding_analytics
        
        render json: {
          success: true,
          data: analytics_data,
          message: "Onboarding analytics retrieved successfully"
        }, status: :ok
      end

      # POST /api/v1/users/:user_id/onboarding_status/sync
      def sync
        Rails.logger.debug "🔄 OnboardingStatusController#sync: Syncing onboarding status for user #{@target_user.auth0_id}"
        
        # Sync onboarding status with actual user data
        sync_result = sync_onboarding_with_user_data
        
        if sync_result[:success]
          render json: {
            success: true,
            data: @target_user.onboarding_status.to_api_hash,
            message: "Onboarding status synchronized successfully",
            metadata: {
              changes_detected: sync_result[:changes],
              sync_performed_at: Time.current.iso8601
            }
          }, status: :ok
        else
          render json: {
            success: false,
            errors: sync_result[:errors],
            message: "Failed to synchronize onboarding status"
          }, status: :unprocessable_entity
        end
      end

      private

      def set_target_user
        user_id = params[:user_id] || params[:id]
        
        # Handle both auth0_id and MongoDB ObjectId
        @target_user = if user_id.match?(/^[a-f\d]{24}$/i)
                        User.find(user_id)
                      else
                        User.find_by(auth0_id: user_id)
                      end
        
        unless @target_user
          render json: {
            success: false,
            message: "User not found"
          }, status: :not_found
          return
        end
      rescue Mongoid::Errors::DocumentNotFound, BSON::ObjectId::Invalid
        render json: {
          success: false,
          message: "User not found"
        }, status: :not_found
      end

      def set_request_context
        @request_context = {
          'request_id' => request.uuid,
          'user_agent' => request.user_agent,
          'ip_address' => request.remote_ip,
          'current_user_id' => current_user.auth0_id,
          'target_user_id' => @target_user.auth0_id,
          'timestamp' => Time.current.iso8601,
          'endpoint' => "#{request.method} #{request.path}"
        }
      end

      def check_rate_limit
        # Implement rate limiting logic
        # For example, using Redis to track requests per user per minute
        rate_limit_key = "onboarding_api:#{current_user.auth0_id}:#{Time.current.strftime('%Y%m%d%H%M')}"
        
        # This is a simplified example - use a proper rate limiting gem in production
        current_requests = Rails.cache.read(rate_limit_key) || 0
        
        if current_requests >= 60 # 60 requests per minute
          render json: {
            success: false,
            message: "Rate limit exceeded. Please try again later.",
            retry_after: 60
          }, status: :too_many_requests
          return
        end
        
        Rails.cache.write(rate_limit_key, current_requests + 1, expires_in: 1.minute)
      end

      def log_request_performance
        start_time = Time.current
        
        yield
        
        duration = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.info "⏱️ OnboardingStatusController: #{action_name} completed in #{duration}ms for user #{@target_user&.auth0_id}"
      end

      def track_api_usage
        # Track API usage for analytics
        usage_data = {
          endpoint: "#{request.method} #{request.path}",
          user_id: current_user.auth0_id,
          target_user_id: @target_user&.auth0_id,
          response_status: response.status,
          timestamp: Time.current.iso8601,
          user_agent: request.user_agent
        }
        
        # Send to analytics service
        # AnalyticsService.track_api_usage(usage_data)
      end

      def validate_step_metadata(step_name, metadata)
        errors = []
        
        case step_name.to_s
        when 'create_grades'
          if metadata['grades_created'].present? && !metadata['grades_created'].is_a?(Integer)
            errors << "grades_created must be an integer"
          end
        when 'upload_learners'
          if metadata['learners_uploaded'].present? && !metadata['learners_uploaded'].is_a?(Integer)
            errors << "learners_uploaded must be an integer"
          end
        when 'send_invites'
          if metadata['invites_sent'].present? && !metadata['invites_sent'].is_a?(Integer)
            errors << "invites_sent must be an integer"
          end
        end
        
        { valid: errors.empty?, errors: errors }
      end

      def requires_skip_reason?(step_name)
        # Define which steps require a reason when skipped
        critical_steps = %w[create_grades upload_learners]
        critical_steps.include?(step_name.to_s)
      end

      def can_force_complete_onboarding?
        current_user == @target_user || 
        current_user.roles.include?('admin') ||
        current_user.roles.include?('super_admin')
      end

      def can_reset_onboarding?
        current_user == @target_user || 
        current_user.roles.include?('admin') ||
        current_user.roles.include?('super_admin')
      end

      def can_view_analytics?
        current_user == @target_user || 
        current_user.roles.include?('admin') ||
        current_user.roles.include?('super_admin')
      end

      def can_skip_current_step?(step_name)
        # Define business rules for which steps can be skipped
        skippable_steps = %w[send_invites admin_onboarding parent_onboarding guest_onboarding]
        skippable_steps.include?(step_name.to_s)
      end

      def estimate_step_time(step_name)
        # Provide estimated completion times for each step
        time_estimates = {
          'create_grades' => 5,
          'upload_learners' => 10,
          'send_invites' => 3,
          'admin_onboarding' => 7,
          'parent_onboarding' => 2,
          'guest_onboarding' => 1
        }
        
        time_estimates[step_name.to_s] || 5
      end

      def get_step_description(step_name)
        descriptions = {
          'create_grades' => 'Set up grade levels and class structures for your school',
          'upload_learners' => 'Import student data using CSV upload or manual entry',
          'send_invites' => 'Send invitation emails to parents, teachers, and staff',
          'admin_onboarding' => 'Complete administrator-specific setup and configuration',
          'parent_onboarding' => 'Set up parent portal access and preferences',
          'guest_onboarding' => 'Configure guest user permissions and access'
        }
        
        descriptions[step_name.to_s] || 'Complete this onboarding step'
      end

      def get_step_prerequisites(step_name)
        prerequisites = {
          'create_grades' => [],
          'upload_learners' => ['create_grades'],
          'send_invites' => ['create_grades', 'upload_learners'],
          'admin_onboarding' => ['create_grades', 'upload_learners', 'send_invites'],
          'parent_onboarding' => [],
          'guest_onboarding' => []
        }
        
        prerequisites[step_name.to_s] || []
      end

      def sync_onboarding_with_user_data
        changes = []
        errors = []
        
        begin
          @target_user.ensure_onboarding_status
          onboarding = @target_user.onboarding_status
          
          # Check if user has created grades
          if @target_user.created_grades.any? && !onboarding.create_grades
            onboarding.create_grades = true
            changes << 'create_grades set to true based on existing grades'
          end
          
          # Check if user has created learners
          if @target_user.created_learners.any? && !onboarding.upload_learners
            onboarding.upload_learners = true
            changes << 'upload_learners set to true based on existing learners'
          end
          
          # Check if user has sent invitations (if invitation models exist)
          if defined?(LearnerInvitation) && @target_user.learner_invitations_sent.any? && !onboarding.send_invites
            onboarding.send_invites = true
            changes << 'send_invites set to true based on existing invitations'
          end
          
          # Auto-complete if ready
          onboarding.auto_complete_if_ready!
          
          if changes.any?
            onboarding.save!
            Rails.logger.info "🔄 Synced onboarding status for user #{@target_user.auth0_id}: #{changes.join(', ')}"
          end
          
          { success: true, changes: changes }
          
        rescue => e
          Rails.logger.error "❌ Failed to sync onboarding status: #{e.message}"
          { success: false, errors: [e.message] }
        end
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