class OnboardingStatus
  include Mongoid::Document
  embedded_in :user, inverse_of: :onboarding_status_detail

  # ======================== CONSTANTS =====================
  PARENT_STEPS = [
    'profile_setup',
    'identity_verification',
    'link_learners',
    'subscription_choice',
    'payment_setup',
    'parent_contact_summary',
    'notification_preferences',
    'terms_acceptance'
  ].freeze

  ADMIN_STEPS = [
    'create_grades',
    'upload_learners',
    'send_invites',
    'admin_onboarding'
  ].freeze

  GUEST_STEPS = [
    'guest_onboarding'
  ].freeze

  DEFAULT_STEPS = [
    'create_grades',
    'upload_learners',
    'send_invites'
  ].freeze

  # ======================== FIELDS ========================
  field :create_grades, type: Boolean, default: false
  field :upload_learners, type: Boolean, default: false
  field :send_invites, type: Boolean, default: false
  field :admin_onboarding_completed, type: Boolean, default: false
  field :parent_onboarding_completed, type: Boolean, default: false
  field :guest_onboarding_completed, type: Boolean, default: false

  field :current_step, type: String
  field :completed_steps, type: Array, default: []
  field :skipped_steps, type: Array, default: []

  field :completion_percentage, type: Float, default: 0.0
  field :client_metadata, type: Hash, default: {}

  field :started_at, type: Time
  field :completed_at, type: Time
  field :total_steps_count, type: Integer, default: 0

  # ======================== CALLBACKS ========================
  before_save :calculate_progress_metrics
  before_save :auto_complete_if_ready!
  before_save :set_timestamps
  after_save  :sync_to_user

  # ======================== METHODS =========================

  def role_step_list
    user_roles = user&.roles || []
    if user_roles.include?('admin')
      ADMIN_STEPS
    elsif user_roles.include?('parent')
      PARENT_STEPS
    elsif user_roles.include?('guest')
      GUEST_STEPS
    else
      DEFAULT_STEPS
    end
  end

  def steps_completed_count
    # Return count of completed steps within the user's role step list
    (completed_steps & role_step_list).size
  end

  def total_steps_count
    role_step_list.size
  end

  def check_role_completion_flags
    user_roles = user&.roles || []

    if user_roles.include?('parent') && (PARENT_STEPS - completed_steps).empty?
      self.parent_onboarding_completed = true
    end

    if user_roles.include?('admin') && (ADMIN_STEPS - completed_steps).empty?
      self.admin_onboarding_completed = true
    end

    if user_roles.include?('guest') && (GUEST_STEPS - completed_steps).empty?
      self.guest_onboarding_completed = true
    end
  end

  def calculate_progress_metrics
    self.total_steps_count = role_step_list.size

    # Update per-role flags if completed_steps matches lists
    check_role_completion_flags

    total_steps = total_steps_count
    return 0.0 if total_steps.zero?

    completed_count = steps_completed_count
    self.completion_percentage = (completed_count.to_f / total_steps * 100).round(2)
  end

  def auto_complete_if_ready!
    if all_steps_completed?
      self.completed_at ||= Time.current
      true
    else
      false
    end
  end

  def all_steps_completed?
    user_roles = user&.roles || []

    if user_roles.include?('admin')
      admin_onboarding_completed || (ADMIN_STEPS - completed_steps).empty?
    elsif user_roles.include?('parent')
      parent_onboarding_completed || (PARENT_STEPS - completed_steps).empty?
    elsif user_roles.include?('guest')
      guest_onboarding_completed || (GUEST_STEPS - completed_steps).empty?
    else
      (create_grades && upload_learners) || (DEFAULT_STEPS - completed_steps).empty?
    end
  end

  def set_timestamps
    self.started_at ||= Time.current if any_step_completed?
  end

  def any_step_completed?
    create_grades || upload_learners || send_invites ||
      admin_onboarding_completed || parent_onboarding_completed || guest_onboarding_completed ||
      completed_steps.any?
  end

  def next_step
    steps = role_step_list
    current_index = steps.index(current_step)
    if current_index && current_index < steps.size - 1
      steps[current_index + 1]
    else
      steps.find { |s| !completed_steps.include?(s) } || steps.last
    end
  end

  def complete_step!(step_name)
    step_name = step_name.to_s.underscore
    case step_name
    when 'create_grades'         then self.create_grades = true
    when 'upload_learners'       then self.upload_learners = true
    when 'send_invites'          then self.send_invites = true
    when 'admin_onboarding'      then self.admin_onboarding_completed = true
    when 'parent_onboarding'     then self.parent_onboarding_completed = true
    when 'guest_onboarding'      then self.guest_onboarding_completed = true
    end

    # Handle array duplication/assignment to ensure Mongoid tracks the array update
    steps = Array(completed_steps).dup
    unless steps.include?(step_name)
      steps << step_name
      self.completed_steps = steps
    end

    self.current_step = next_step
    calculate_progress_metrics
    auto_complete_if_ready!
    save!
  end

  def skip_step!(step_name, reason: nil)
    step_name = step_name.to_s.underscore
    skip_data = { step: step_name, reason: reason, skipped_at: Time.current }

    skips = Array(skipped_steps).dup
    skips << skip_data
    self.skipped_steps = skips

    self.current_step = next_step
    calculate_progress_metrics
    save!
  end

  def reset!
    self.attributes = {
      create_grades: false,
      upload_learners: false,
      send_invites: false,
      admin_onboarding_completed: false,
      parent_onboarding_completed: false,
      guest_onboarding_completed: false,
      current_step: nil,
      completed_steps: [],
      skipped_steps: [],
      completion_percentage: 0.0,
      completed_at: nil,
      started_at: nil
    }
    save!
  end

  def assign_attributes_from_api(attrs)
    return if attrs.blank?

    attrs.each do |key, value|
      snake_key = key.to_s.underscore
      if respond_to?("#{snake_key}=")
        send("#{snake_key}=", value)
      end
    end
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
      total_steps: total_steps_count
    }
  end

  def as_json(options = {})
    json = super(options || {})
    json['parent_onboarding_completed'] = parent_onboarding_completed
    json['parentOnboardingCompleted'] = parent_onboarding_completed
    json['admin_onboarding_completed'] = admin_onboarding_completed
    json['adminOnboardingCompleted'] = admin_onboarding_completed
    json['guest_onboarding_completed'] = guest_onboarding_completed
    json['guestOnboardingCompleted'] = guest_onboarding_completed
    json['completion_percentage'] = completion_percentage
    json['completionPercentage'] = completion_percentage
    json['completed_steps'] = completed_steps
    json['completedSteps'] = completed_steps
    json['total_steps_count'] = total_steps_count
    json['totalStepsCount'] = total_steps_count
    json
  end

  private

  # 🔑 Sync progress & completion flags back to the parent user
  def sync_to_user
    completed = all_steps_completed?
    progress = completion_percentage

    user.onboarding_completed = completed if user.respond_to?(:onboarding_completed=)
    user.onboarding_progress = progress if user.respond_to?(:onboarding_progress=)

    user.set(
      onboarding_completed: completed,
      onboarding_progress: progress
    )
  end
end
