# app/services/user_services/create_user_service.rb
module UserServices
  class CreateUserService
    Result = Struct.new(:success?, :user, :errors, keyword_init: true)

    def initialize(user_params:)
      @user_params = user_params
    end

    def call
      Rails.logger.info "🚀 [CreateUserService] Starting with params: #{@user_params.except(:email, :name).inspect}"
      
      # Find or initialize user
      user = User.find_or_initialize_by(auth0_id: @user_params[:auth0_id])
      was_new_record = user.new_record?
      
      Rails.logger.info "   User #{was_new_record ? 'NEW' : 'EXISTS'}: #{user.auth0_id}"
      
      # Assign basic attributes (exclude invitation_token)
      user.assign_attributes(@user_params.except(:invitation_token))

      # Process invitation if provided
      invitation_token = @user_params[:invitation_token]
      invitation = process_invitation(user, invitation_token) if invitation_token.present?

      # Save user
      if user.save
        Rails.logger.info "✅ [CreateUserService] User saved successfully"
        
        # Initialize onboarding for new users
        user.initialize_onboarding_status if was_new_record
        
        # Link learners if invitation exists
        link_learners_from_invitation(user, invitation) if invitation&.persisted?
        
        Result.new(success?: true, user: user.reload.to_api_hash, errors: [])
      else
        Rails.logger.error "❌ [CreateUserService] User save failed: #{user.errors.full_messages}"
        Result.new(success?: false, user: nil, errors: user.errors.full_messages)
      end
    rescue => e
      Rails.logger.error "❌ [CreateUserService] Exception: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      Result.new(success?: false, user: nil, errors: [e.message])
    end

    private

    def process_invitation(user, invitation_token)
      Rails.logger.info "🎫 [CreateUserService] Processing invitation_token: #{invitation_token}"
      
      invitation = Invitation.find_by(token: invitation_token, :status.in => ['pending', 'verified'])
      
      if invitation.nil?
        Rails.logger.warn "⚠️ [CreateUserService] Invitation NOT FOUND or already accepted"
        return nil
      end
      
      Rails.logger.info "🎫 [CreateUserService] Found invitation:"
      Rails.logger.info "   ID: #{invitation.id}"
      Rails.logger.info "   Status: #{invitation.status}"
      Rails.logger.info "   School ID: #{invitation.school_id}"
      Rails.logger.info "   Learner IDs: #{invitation.learner_ids.inspect}"
      Rails.logger.info "   Learner Numbers: #{invitation.learner_numbers.inspect}"
      Rails.logger.info "   Recipient Phone: #{invitation.recipient_phone_number}"
      
      # Update user from invitation
      user.phone_number ||= invitation.recipient_phone_number
      user.invited_via ||= invitation.invited_via
      
      # Add parent role if not present
      unless user.roles.include?('parent')
        user.roles << 'parent'
        Rails.logger.info "   Added 'parent' role"
      end
      
      # Add school if not present
      if invitation.school_id.present?
        school_id_str = invitation.school_id.to_s
        user.school_ids ||= []
        
        unless user.school_ids.map(&:to_s).include?(school_id_str)
          # Convert to BSON::ObjectId for consistency
          user.school_ids << BSON::ObjectId.from_string(school_id_str)
          Rails.logger.info "   Added school_id: #{school_id_str}"
        else
          Rails.logger.info "   School already linked: #{school_id_str}"
        end
      end
      
      invitation
    end

    def link_learners_from_invitation(user, invitation)
      Rails.logger.info "🔗 [CreateUserService] Linking learners from invitation"
      
      # Mark invitation as accepted
      invitation.update(status: 'accepted', accepted_at: Time.current)
      Rails.logger.info "   Invitation marked as accepted"
      
      # Check if learner_ids exist
      if invitation.learner_ids.blank?
        Rails.logger.warn "⚠️ [CreateUserService] No learner_ids in invitation!"
        return
      end
      
      Rails.logger.info "   Calling ParentLinkageService with #{invitation.learner_ids.count} learner(s)"
      Rails.logger.info "   Learner IDs: #{invitation.learner_ids.inspect}"
      
      # Call ParentLinkageService
      linkage_result = ParentLinkageService.new(
        user: user,
        learner_ids: invitation.learner_ids
      ).call
      
      if linkage_result
        Rails.logger.info "✅ [CreateUserService] ParentLinkageService completed successfully"
      else
        Rails.logger.error "❌ [CreateUserService] ParentLinkageService failed"
      end
      
    rescue => e
      Rails.logger.error "❌ [CreateUserService] Error linking learners: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end
  end
end