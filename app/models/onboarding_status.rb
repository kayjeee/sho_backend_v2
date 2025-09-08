# app/models/onboarding_status.rb
class OnboardingStatus
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic # Allows storing arbitrary metadata safely

  # -------------------
  # Embedded document
  # -------------------
  embedded_in :user

  # -------------------
  # Core onboarding steps
  # -------------------
  field :create_grades,               type: Mongoid::Boolean, default: false
  field :upload_learners,             type: Mongoid::Boolean, default: false
  field :send_invites,                type: Mongoid::Boolean, default: false

  # -------------------
  # Role-specific completion
  # -------------------
  field :admin_onboarding_completed,  type: Mongoid::Boolean, default: false
  field :parent_onboarding_completed, type: Mongoid::Boolean, default: false
  field :guest_onboarding_completed,  type: Mongoid::Boolean, default: false

  # -------------------
  # Overall progress
  # -------------------
  field :completed,                   type: Mongoid::Boolean, default: false
  field :current_step,                type: String
  field :skipped_steps,               type: Array, default: []

  field :steps_completed_count,       type: Integer, default: 0
  field :total_steps_count,           type: Integer, default: 6
  field :completion_percentage,       type: Float, default: 0.0

  # -------------------
  # Metadata & audit
  # -------------------
  field :started_at,                  type: Time
  field :completed_at,                type: Time
  field :last_updated,                type: Time
  field :version,                     type: Integer, default: 1
  field :client_metadata,             type: Hash, default: {}

  # -------------------
  # Indexes
  # -------------------
  index({ completed: 1 })
  index({ current_step: 1 })
  index({ completion_percentage: 1 })
  index({ last_updated: 1 })

  # -------------------
  # Validations
  # -------------------
  validates :steps_completed_count, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: :total_steps_count }
  validates :total_steps_count, numericality: { greater_than: 0 }
  validates :completion_percentage, numericality: { in: 0.0..100.0 }
  validates :current_step, inclusion: {
    in: %w[create_grades upload_learners send_invites admin_onboarding parent_onboarding guest_onboarding completion],
    allow_nil: true
  }

  validate :validate_step_dependencies
  validate :validate_completion_consistency
  validate :validate_role_specific_completion
  validate :validate_skipped_steps_format

  # -------------------
  # Callbacks
  # -------------------
  before_save :set_last_updated
  before_save :calculate_progress_metrics
  before_save :set_started_at_if_first_step
  before_save :update_version
  after_save  :log_progress_change

  # ============================
  # INSTANCE METHODS
  # ============================

  # Update timestamps
  def set_last_updated
    self.last_updated = Time.current
    self.client_metadata['last_sync_at'] = Time.current
  end

  def update_version
    self.version = (version || 0) + 1
  end

  def touch_last_updated!
    set_last_updated
    save!
  end

  # Progress calculations
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

  # Step handling
  def any_step_completed?
    create_grades || upload_learners || send_invites ||
      admin_onboarding_completed || parent_onboarding_completed || guest_onboarding_completed
  end

  def set_started_at_if_first_step
    self.started_at ||= Time.current if any_step_completed?
  end

  def role_specific_completed?
    return true unless user

    user_roles = user.roles || []
    return admin_onboarding_completed if user_roles.include?('admin')
    return parent_onboarding_completed if user_roles.include?('parent')
    return guest_onboarding_completed if user_roles.include?('guest')

    true
  end

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

  def auto_complete_if_ready!
    all_base_steps_complete = create_grades && upload_learners && send_invites
    role_step_complete = role_specific_completed?

    if all_base_steps_complete && role_step_complete && !completed
      self.completed = true
      self.completed_at = Time.current
      self.current_step = nil
      trigger_completion_event
    elsif completed && (!all_base_steps_complete || !role_step_complete)
      self.completed = false
      self.completed_at = nil
      self.current_step = next_step
    end
  end

  # Complete a step
  def complete_step!(step_name, skip_validation: false)
    case step_name.to_s
    when 'create_grades' then self.create_grades = true
    when 'upload_learners'
      raise ArgumentError, "Cannot complete upload_learners before create_grades" unless create_grades || skip_validation
      self.upload_learners = true
    when 'send_invites'
      raise ArgumentError, "Cannot complete send_invites before upload_learners" unless upload_learners || skip_validation
      self.send_invites = true
    when 'admin_onboarding' then self.admin_onboarding_completed = true
    when 'parent_onboarding' then self.parent_onboarding_completed = true
    when 'guest_onboarding' then self.guest_onboarding_completed = true
    else
      raise ArgumentError, "Unknown step: #{step_name}"
    end

    self.current_step = next_step
    auto_complete_if_ready!
    save!
  end

  # Skip a step
  def skip_step!(step_name, reason: nil)
    self.skipped_steps << step_name.to_s unless skipped_steps.include?(step_name.to_s)
    self.client_metadata['skipped_steps'] ||= []
    self.client_metadata['skipped_steps'] << { step: step_name, reason: reason, skipped_at: Time.current.iso8601 }
    self.current_step = next_step
    save!
  end

  # Reset onboarding
  def reset!(reset_by: nil)
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

    self.client_metadata['reset_history'] ||= []
    self.client_metadata['reset_history'] << { reset_at: Time.current.iso8601, reset_by: reset_by }

    save!
  end

  # Serialization
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
      metadata: client_metadata
    }
  end

  private

  # Validations
  def validate_step_dependencies
    errors.add(:upload_learners, "cannot be completed before create_grades") if upload_learners && !create_grades
    errors.add(:send_invites, "cannot be completed before upload_learners") if send_invites && !upload_learners
  end

  def validate_completion_consistency
    errors.add(:completed_at, "must be set when onboarding is completed") if completed && completed_at.nil?
    errors.add(:completed_at, "should not be set when onboarding is not completed") if !completed && completed_at.present?
  end

  def validate_role_specific_completion
    return unless user
    roles = user.roles || []

    errors.add(:admin_onboarding_completed, "cannot be true for non-admin users") if admin_onboarding_completed && !roles.include?('admin')
    errors.add(:parent_onboarding_completed, "cannot be true for non-parent users") if parent_onboarding_completed && !roles.include?('parent')
    errors.add(:guest_onboarding_completed, "cannot be true for non-guest users") if guest_onboarding_completed && !roles.include?('guest')
  end

  def validate_skipped_steps_format
    return unless skipped_steps.is_a?(Array)
    valid_steps = %w[create_grades upload_learners send_invites admin_onboarding parent_onboarding guest_onboarding]
    invalid = skipped_steps - valid_steps
    errors.add(:skipped_steps, "contains invalid steps: #{invalid.join(', ')}") if invalid.any?
  end

  # Logging & events
  def log_progress_change
    return unless saved_change_to_completion_percentage?
    old = saved_change_to_completion_percentage[0] || 0.0
    new_val = completion_percentage
    Rails.logger.info "📊 Onboarding progress for user #{user.auth0_id}: #{old}% → #{new_val}%"
  end

  def trigger_completion_event
    # Placeholder for webhook/job
  end
end
