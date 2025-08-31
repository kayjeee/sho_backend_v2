# app/models/onboarding_status.rb
class OnboardingStatus
  include Mongoid::Document
  include Mongoid::Timestamps

  # Embed this document within the User model
  embedded_in :user

  # Core onboarding step tracking fields
  field :create_grades,               type: Mongoid::Boolean, default: false
  field :upload_learners,             type: Mongoid::Boolean, default: false
  field :send_invites,                type: Mongoid::Boolean, default: false
  
  # Role-specific onboarding completion tracking
  field :admin_onboarding_completed,  type: Mongoid::Boolean, default: false
  field :parent_onboarding_completed, type: Mongoid::Boolean, default: false
  field :guest_onboarding_completed,  type: Mongoid::Boolean, default: false
  
  # Overall completion and progress tracking
  field :completed,                   type: Mongoid::Boolean, default: false
  field :last_updated,                type: Time
  field :started_at,                  type: Time
  field :completed_at,                type: Time
  field :current_step,                type: String
  field :skipped_steps,               type: Array, default: []
  
  # Progress tracking for analytics and user feedback
  field :steps_completed_count,       type: Integer, default: 0
  field :total_steps_count,           type: Integer, default: 6
  field :completion_percentage,       type: Float, default: 0.0
  
  # Metadata for tracking and debugging
  field :version,                     type: Integer, default: 1
  field :last_sync_at,                type: Time
  field :client_metadata,             type: Hash, default: {}

  # Validation rules to ensure data integrity
  validates :steps_completed_count, numericality: { 
    greater_than_or_equal_to: 0, 
    less_than_or_equal_to: :total_steps_count 
  }
  validates :total_steps_count, numericality: { greater_than: 0 }
  validates :completion_percentage, numericality: { in: 0.0..100.0 }
  validates :current_step, inclusion: { 
    in: %w[create_grades upload_learners send_invites admin_onboarding parent_onboarding guest_onboarding completion],
    allow_nil: true 
  }
  
  # Custom validation methods
  validate :validate_step_dependencies
  validate :validate_completion_consistency
  validate :validate_role_specific_completion
  validate :validate_skipped_steps_format

  # Callbacks to maintain data consistency
  before_save :set_last_updated
  before_save :calculate_progress_metrics
  before_save :set_started_at_if_first_step
  before_save :update_version
  after_save :log_progress_change
  after_save :trigger_analytics_event

  # Indexes for performance optimization
  index({ completed: 1 })
  index({ current_step: 1 })
  index({ completion_percentage: 1 })
  index({ last_updated: 1 })

  # ========================= INSTANCE METHODS =========================

  def set_last_updated
    self.last_updated = Time.current
    self.last_sync_at = Time.current
  end

  def update_version
    self.version = (version || 0) + 1
  end

  def touch_last_updated!
    self.last_updated = Time.current
    self.last_sync_at = Time.current
    save!
  end

  # Calculate completion percentage and step counts
  def calculate_progress_metrics
    completed_steps = count_completed_steps
    self.steps_completed_count = completed_steps
    self.completion_percentage = calculate_percentage(completed_steps)
  end

  def count_completed_steps
    base_steps = [create_grades, upload_learners, send_invites].count(true)
    role_steps = role_specific_completed? ? 1 : 0
    base_steps + role_steps
  end

  def calculate_percentage(completed_steps)
    return 0.0 if total_steps_count <= 0
    (completed_steps.to_f / total_steps_count * 100).round(2)
  end

  # Set started_at timestamp when first step is completed
  def set_started_at_if_first_step
    if started_at.nil? && any_step_completed?
      self.started_at = Time.current
    end
  end

  # Determine if any step has been completed
  def any_step_completed?
    create_grades || upload_learners || send_invites || 
    admin_onboarding_completed || parent_onboarding_completed || guest_onboarding_completed
  end

  # Check if role-specific onboarding is completed based on user roles
  def role_specific_completed?
    user_roles = user&.roles || []
    
    return admin_onboarding_completed if user_roles.include?('admin')
    return parent_onboarding_completed if user_roles.include?('parent')
    return guest_onboarding_completed if user_roles.include?('guest')
    
    # Default to true for users without specific roles
    true
  end

  # Automatically mark onboarding as complete when all required steps are done
  def auto_complete_if_ready!
    all_base_steps_complete = create_grades && upload_learners && send_invites
    role_step_complete = role_specific_completed?
    
    if all_base_steps_complete && role_step_complete && !completed
      self.completed = true
      self.completed_at = Time.current
      self.current_step = nil
      Rails.logger.info "✅ Onboarding auto-completed for user #{user.auth0_id}"
      
      # Trigger completion webhook or notification
      trigger_completion_event
      
    elsif completed && (!all_base_steps_complete || !role_step_complete)
      # Handle case where completion status needs to be reverted
      self.completed = false
      self.completed_at = nil
      self.current_step = determine_current_step
      Rails.logger.warn "⚠️ Onboarding completion reverted for user #{user.auth0_id}"
    end
  end

  # Get the next recommended step based on current progress
  def next_step
    return nil if completed
    
    return 'create_grades' unless create_grades
    return 'upload_learners' unless upload_learners
    return 'send_invites' unless send_invites
    
    user_roles = user&.roles || []
    return 'admin_onboarding' if user_roles.include?('admin') && !admin_onboarding_completed
    return 'parent_onboarding' if user_roles.include?('parent') && !parent_onboarding_completed
    return 'guest_onboarding' if user_roles.include?('guest') && !guest_onboarding_completed
    
    'completion'
  end

  # Determine current step based on completion status
  def determine_current_step
    return nil if completed
    next_step
  end

  # Mark a specific step as completed with comprehensive error handling
  def complete_step!(step_name, skip_validation: false)
    step_name = step_name.to_s
    
    case step_name
    when 'create_grades'
      complete_create_grades_step(skip_validation)
    when 'upload_learners'
      complete_upload_learners_step(skip_validation)
    when 'send_invites'
      complete_send_invites_step(skip_validation)
    when 'admin_onboarding'
      complete_admin_onboarding_step
    when 'parent_onboarding'
      complete_parent_onboarding_step
    when 'guest_onboarding'
      complete_guest_onboarding_step
    else
      raise ArgumentError, "Unknown step: #{step_name}"
    end
    
    # Update current step and check for completion
    self.current_step = next_step
    auto_complete_if_ready!
    save!
    
    Rails.logger.info "✅ Step '#{step_name}' completed for user #{user.auth0_id}"
  end

  # Skip a step and add it to skipped steps array
  def skip_step!(step_name, reason: nil)
    step_name = step_name.to_s
    
    unless skipped_steps.include?(step_name)
      self.skipped_steps << step_name
    end
    
    # Store skip metadata
    skip_metadata = {
      step: step_name,
      reason: reason,
      skipped_at: Time.current.iso8601,
      user_agent: client_metadata['user_agent']
    }
    
    self.client_metadata['skipped_steps'] ||= []
    self.client_metadata['skipped_steps'] << skip_metadata
    
    # Log the skip reason if provided
    Rails.logger.info "⏭️ User #{user.auth0_id} skipped step '#{step_name}'" + 
                     (reason ? " - Reason: #{reason}" : "")
    
    # Move to next step
    self.current_step = next_step
    save!
  end

  # Reset onboarding status to initial state
  def reset!
    # Store reset metadata for audit trail
    reset_metadata = {
      reset_at: Time.current.iso8601,
      previous_completion_percentage: completion_percentage,
      previous_completed_steps: steps_completed_count,
      reset_by: client_metadata['reset_by']
    }
    
    # Reset all fields
    self.create_grades = false
    self.upload_learners = false
    self.send_invites = false
    self.admin_onboarding_completed = false
    self.parent_onboarding_completed = false
    self.guest_onboarding_completed = false
    self.completed = false
    self.completed_at = nil
    self.started_at = nil
    self.current_step = 'create_grades'
    self.skipped_steps = []
    self.steps_completed_count = 0
    self.completion_percentage = 0.0
    
    # Store reset metadata
    self.client_metadata['reset_history'] ||= []
    self.client_metadata['reset_history'] << reset_metadata
    
    save!
    Rails.logger.info "🔄 Onboarding reset for user #{user.auth0_id}"
  end

  # Serialize to match frontend's expected camelCase format
  def to_api_hash
    {
      createGrades: create_grades,
      uploadLearners: upload_learners,
      sendInvites: send_invites,
      adminOnboardingCompleted: admin_onboarding_completed,
      parentOnboardingCompleted: parent_onboarding_completed,
      guestOnboardingCompleted: guest_onboarding_completed,
      completed: completed,
      lastUpdated: last_updated&.iso8601,
      startedAt: started_at&.iso8601,
      completedAt: completed_at&.iso8601,
      currentStep: current_step,
      nextStep: next_step,
      skippedSteps: skipped_steps,
      progress: {
        stepsCompleted: steps_completed_count,
        totalSteps: total_steps_count,
        percentage: completion_percentage
      },
      metadata: {
        version: version,
        lastSyncAt: last_sync_at&.iso8601
      }
    }
  end

  # Handle camelCase input from frontend
  def assign_attributes_from_api(attrs = {})
    mapping = {
      'createGrades' => :create_grades,
      'uploadLearners' => :upload_learners,
      'sendInvites' => :send_invites,
      'adminOnboardingCompleted' => :admin_onboarding_completed,
      'parentOnboardingCompleted' => :parent_onboarding_completed,
      'guestOnboardingCompleted' => :guest_onboarding_completed,
      'completed' => :completed,
      'currentStep' => :current_step,
      'skippedSteps' => :skipped_steps
    }

    attrs.each do |key, value|
      field_name = mapping[key] || key.to_s.underscore
      if respond_to?("#{field_name}=")
        send("#{field_name}=", value)
      end
    end
  end

  private

  # Step completion methods with validation
  def complete_create_grades_step(skip_validation)
    self.create_grades = true
    self.current_step = 'upload_learners'
  end

  def complete_upload_learners_step(skip_validation)
    unless create_grades || skip_validation
      raise ArgumentError, "Cannot complete upload_learners before create_grades"
    end
    self.upload_learners = true
    self.current_step = 'send_invites'
  end

  def complete_send_invites_step(skip_validation)
    unless upload_learners || skip_validation
      raise ArgumentError, "Cannot complete send_invites before upload_learners"
    end
    self.send_invites = true
    self.current_step = determine_role_specific_step
  end

  def complete_admin_onboarding_step
    self.admin_onboarding_completed = true
  end

  def complete_parent_onboarding_step
    self.parent_onboarding_completed = true
  end

  def complete_guest_onboarding_step
    self.guest_onboarding_completed = true
  end

  def determine_role_specific_step
    user_roles = user&.roles || []
    return 'admin_onboarding' if user_roles.include?('admin')
    return 'parent_onboarding' if user_roles.include?('parent')
    return 'guest_onboarding' if user_roles.include?('guest')
    'completion'
  end

  # Validation methods
  def validate_step_dependencies
    if upload_learners && !create_grades
      errors.add(:upload_learners, "cannot be completed before create_grades")
    end
    
    if send_invites && !upload_learners
      errors.add(:send_invites, "cannot be completed before upload_learners")
    end
  end

  def validate_completion_consistency
    if completed && completed_at.nil?
      errors.add(:completed_at, "must be set when onboarding is completed")
    end
    
    if !completed && completed_at.present?
      errors.add(:completed_at, "should not be set when onboarding is not completed")
    end
  end

  def validate_role_specific_completion
    return unless user
    
    user_roles = user.roles || []
    
    if admin_onboarding_completed && !user_roles.include?('admin')
      errors.add(:admin_onboarding_completed, "cannot be true for non-admin users")
    end
    
    if parent_onboarding_completed && !user_roles.include?('parent')
      errors.add(:parent_onboarding_completed, "cannot be true for non-parent users")
    end
    
    if guest_onboarding_completed && !user_roles.include?('guest')
      errors.add(:guest_onboarding_completed, "cannot be true for non-guest users")
    end
  end

  def validate_skipped_steps_format
    return unless skipped_steps.is_a?(Array)
    
    valid_steps = %w[create_grades upload_learners send_invites admin_onboarding parent_onboarding guest_onboarding]
    invalid_steps = skipped_steps - valid_steps
    
    if invalid_steps.any?
      errors.add(:skipped_steps, "contains invalid steps: #{invalid_steps.join(', ')}")
    end
  end

  # Event handling methods
  def log_progress_change
    if saved_change_to_completion_percentage?
      old_percentage = saved_change_to_completion_percentage[0] || 0.0
      new_percentage = completion_percentage
      
      Rails.logger.info "📊 Onboarding progress for user #{user.auth0_id}: " +
                       "#{old_percentage}% → #{new_percentage}%"
    end
  end

  def trigger_analytics_event
    return unless saved_change_to_completion_percentage? || saved_change_to_completed?
    
    # Trigger analytics event (implement based on your analytics system)
    # AnalyticsService.track_onboarding_progress(user, self)
  end

  def trigger_completion_event
    # Trigger completion webhook or notification
    # OnboardingCompletionJob.perform_async(user.id)
  end
end