# app/models/onboarding_status.rb
class OnboardingStatus
  include Mongoid::Document
  embedded_in :user, inverse_of: :onboarding_status_detail

  # ─── Canonical parent step order (single source of truth) ───
  PARENT_STEPS = %w[
    PROFILE_SETUP
    IDENTITY_VERIFICATION
    LINK_LEARNERS
    SUBSCRIPTION_CHOICE
    PAYMENT_SETUP
    PARENT_CONTACT_SUMMARY
    NOTIFICATION_PREFERENCES
    TERMS_ACCEPTANCE
  ].freeze

  # ======================== FIELDS ========================
  # Legacy admin booleans – keep for now, admin flow untouched
  field :create_grades,                    type: Boolean, default: false
  field :upload_learners,                  type: Boolean, default: false
  field :send_invites,                     type: Boolean, default: false
  field :admin_onboarding_completed,       type: Boolean, default: false
  field :parent_onboarding_completed,      type: Boolean, default: false
  field :guest_onboarding_completed,       type: Boolean, default: false

  field :current_step,        type: String
  field :completed_steps,     type: Array,  default: []
  field :skipped_steps,       type: Array,  default: []

  field :completion_percentage, type: Float,   default: 0.0
  field :client_metadata,       type: Hash,    default: {}

  field :started_at,            type: Time
  field :completed_at,          type: Time
  field :total_steps_count,     type: Integer, default: 0

  # ======================== CALLBACKS ========================
  before_save :calculate_progress_metrics
  before_save :set_timestamps
  after_save  :sync_to_user

  # ===================== PARENT FLOW METHODS ================

  # Returns the next incomplete parent step, or 'COMPLETE' if all done.
  def next_parent_step
    PARENT_STEPS.each do |step|
      return step unless completed_steps.include?(step)
    end
    'COMPLETE'
  end

  # Marks a single parent step as done, advances current_step, and
  # flips the legacy boolean when the very last step is reached.
  def mark_parent_step_complete!(step_name)
    step_name = step_name.to_s.strip.upcase

    unless PARENT_STEPS.include?(step_name)
      raise ArgumentError, "Unknown parent onboarding step: #{step_name}"
    end

    # Idempotent – skip if already recorded
    unless completed_steps.include?(step_name)
      self.completed_steps = completed_steps + [step_name]   # avoid in-place mutation detection issues
    end

    # Advance current_step to whatever is next
    self.current_step = next_parent_step

    # If we just finished the last step, flip the legacy boolean and
    # stamp the completion time so the rest of the app knows this user
    # is fully onboarded.
    if current_step == 'COMPLETE'
      self.parent_onboarding_completed = true
      self.completed_at = Time.current
    end

    # Recalculate percentage based on parent steps specifically
    recalculate_parent_progress

    save!
  end

  # Returns the percentage of parent steps completed (0.0–100.0).
  def parent_completion_percentage
    return 0.0 if PARENT_STEPS.empty?
    completed_parent = completed_steps.count { |s| PARENT_STEPS.include?(s.to_s.upcase) }
    (completed_parent.to_f / PARENT_STEPS.size * 100).round(2)
  end

  # ===================== EXISTING METHODS (kept for admin flow) ===

  def steps_completed_count
    [create_grades, upload_learners, send_invites,
     admin_onboarding_completed, parent_onboarding_completed,
     guest_onboarding_completed].count(true)
  end

  def calculate_progress_metrics
    # For parent users we use the parent-specific calculation;
    # for others fall back to the legacy boolean-based one.
    if user&.roles&.include?('parent')
      self.completion_percentage = parent_completion_percentage
    else
      total_steps = total_steps_count
      return if total_steps.zero?
      self.completion_percentage = (steps_completed_count.to_f / total_steps * 100).round(2)
    end
  end

  def auto_complete_if_ready!
    if all_steps_completed?
      self.completed_at = Time.current
      true
    else
      false
    end
  end

  def all_steps_completed?
    user_roles = user&.roles || []

    if user_roles.include?('admin')
      create_grades && upload_learners && send_invites && admin_onboarding_completed
    elsif user_roles.include?('parent')
      parent_onboarding_completed   # set by mark_parent_step_complete! when last step finishes
    elsif user_roles.include?('guest')
      guest_onboarding_completed
    else
      create_grades && upload_learners
    end
  end

  def set_timestamps
    self.started_at ||= Time.current if any_step_completed?
  end

  def any_step_completed?
    completed_steps.any? ||
      create_grades || upload_learners || send_invites ||
      admin_onboarding_completed || parent_onboarding_completed || guest_onboarding_completed
  end

  # Legacy next_step for admin flow – unchanged
  def next_step
    steps = %w[create_grades upload_learners send_invites admin_onboarding]
    current_index = steps.index(current_step)
    return steps[current_index + 1] if current_index && current_index < steps.size - 1
    current_step
  end

  # Legacy complete_step! kept for admin flow
  def complete_step!(step_name)
    case step_name
    when 'create_grades'         then self.create_grades = true
    when 'upload_learners'       then self.upload_learners = true
    when 'send_invites'          then self.send_invites = true
    when 'admin_onboarding'      then self.admin_onboarding_completed = true
    when 'parent_onboarding'     then self.parent_onboarding_completed = true
    when 'guest_onboarding'      then self.guest_onboarding_completed = true
    end

    self.completed_steps << step_name unless completed_steps.include?(step_name)
    self.current_step = next_step
    auto_complete_if_ready!
    save!
  end

  def skip_step!(step_name, reason: nil)
    skip_data = { step: step_name, reason: reason, skipped_at: Time.current }
    self.skipped_steps << skip_data
    self.current_step = next_step
    save!
  end

  def reset!
    self.attributes = {
      create_grades: false, upload_learners: false, send_invites: false,
      admin_onboarding_completed: false, parent_onboarding_completed: false,
      guest_onboarding_completed: false,
      current_step: nil, completed_steps: [], skipped_steps: [],
      completion_percentage: 0.0, completed_at: nil
    }
    save!
  end

  def to_api_hash
    {
      create_grades: create_grades,
      upload_learners: upload_learners,
      send_invites: send_invites,
      admin_onboarding_completed: admin_onboarding_completed,
      parent_onboarding_completed: parent_onboarding_completed,
      guest_onboarding_completed: guest_onboarding_completed,
      current_step: current_step,
      completed_steps: completed_steps,
      skipped_steps: skipped_steps,
      completion_percentage: completion_percentage,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      total_steps: total_steps_count,
      # Parent-specific fields the frontend needs
      parent_steps: PARENT_STEPS,
      next_parent_step: next_parent_step,
      parent_completion_percentage: parent_completion_percentage
    }
  end

  private

  def recalculate_parent_progress
    self.completion_percentage = parent_completion_percentage
  end

  def sync_to_user
    user.set(
      onboarding_completed: all_steps_completed?,
      onboarding_progress: completion_percentage
    )
  end
end