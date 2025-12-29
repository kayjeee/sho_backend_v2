# app/services/parent_linkage_service.rb
class ParentLinkageService
  def initialize(user:, learner_ids:)
    @user = user
    @learner_ids = Array(learner_ids).map(&:to_s)
  end

  def call
    Rails.logger.info "👨‍👩‍👧 [ParentLinkageService] Starting for user: #{@user.auth0_id}"
    Rails.logger.info "   Learner IDs to link: #{@learner_ids.inspect}"
    
    return false if @learner_ids.blank?

    linked_count = 0
    @learner_ids.each do |learner_id|
      learner = Learner.find(learner_id)
      
      learner.parent_auth0_ids ||= []
      unless learner.parent_auth0_ids.include?(@user.auth0_id)
        learner.parent_auth0_ids << @user.auth0_id
        learner.save
        linked_count += 1
        Rails.logger.info "   ✅ Linked learner: #{learner.full_name} (#{learner.id})"
      else
        Rails.logger.info "   ⏭️ Already linked: #{learner.full_name} (#{learner.id})"
      end
    end
    
    Rails.logger.info "✅ [ParentLinkageService] Linked #{linked_count} new learner(s)"
    true
  rescue => e
    Rails.logger.error "❌ [ParentLinkageService] Error: #{e.message}"
    false
  end
end