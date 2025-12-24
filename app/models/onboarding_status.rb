# app/models/onboarding_status.rb
class OnboardingStatus
  include Mongoid::Document
  embedded_in :user, inverse_of: :onboarding_status_detail

  # ======================== FIELDS ========================
  field :create_grades, type: Boolean, default: false
  field :upload_learners, type: Boolean, default: false
  field :send_invites, type: Boolean, default: false
  field :admin_onboarding_completed, type: Boolean, default: false
  field :parent_onboarding_completed, type: Boolean, default: false
  field :guest_onboarding_completed, type: Boolean, default: false
  field :completed, type: Boolean, default: false

  field :current_step, type: String
  field :completed_steps, type: Array, default: []
  field :skipped_steps, type: Array, default: []

  field :completion_percentage, type: Float, default: 0.0
  field :client_metadata, type: Hash, default: {}

  field :started_at, type: Time
  field :completed_at, type: Time
  field :total_steps_count, type: Integer, default: 0

  # ======================== CALLBACKS ========================
  after_initialize :set_defaults, if: :new_record?
  before_save :calculate_completion_percentage
  before_save :set_timestamps

  # ======================== METHODS =========================

  def steps_completed_count
    [
      create_grades, upload_learners, send_invites,
      admin_onboarding_completed, parent_onboarding_completed,
      guest_onboarding_completed
    ].count(true)
  end

  def calculate_completion_percentage
    return self.completion_percentage = 100.0 if completed?
    return self.completion_percentage = 0.0 if total_steps_count.zero?

    completed_count = steps_completed_count
    percentage = (completed_count.to_f / total_steps_count * 100).round
    self.completion_percentage = [percentage, 100].min
  end

  def all_steps_completed?
    user_roles = user.roles.map(&:downcase)

    if user_roles.include?('admin')
      create_grades && upload_learners && send_invites && admin_onboarding_completed
    elsif user_roles.include?('parent')
      parent_onboarding_completed
    elsif user_roles.include?('guest')
      guest_onboarding_completed
    else
      create_grades && upload_learners
    end
  end

  def complete_step!(step_name)
    self[step_name] = true if has_attribute?(step_name)
    self.completed_steps << step_name unless completed_steps.include?(step_name)
    self.current_step = next_step
    auto_complete_if_ready!
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
      total_steps: total_steps_count
    }
  end

  private

  def set_defaults
    self.started_at ||= Time.current
    self.completed_steps ||= []
    self.skipped_steps ||= []
    self.client_metadata ||= {}
    set_total_steps_based_on_user_roles
    set_current_step_based_on_user_roles
  end

  def set_total_steps_based_on_user_roles
    roles = user.roles.map(&:downcase)
    self.total_steps_count = case
                             when roles.include?('admin') then 4
                             when roles.include?('parent') then 1
                             when roles.include?('guest') then 1
                             else 3
                             end
  end

  def set_current_step_based_on_user_roles
    roles = user.roles.map(&:downcase)
    self.current_step ||= case
                          when roles.include?('admin') then 'create_grades'
                          when roles.include?('parent') then 'parent_onboarding'
                          when roles.include?('guest') then 'guest_onboarding'
                          else 'create_grades'
                          end
  end

  def set_timestamps
    self.completed_at = Time.current if all_steps_completed? && completed_at.nil?
  end

  def auto_complete_if_ready!
    if all_steps_completed?
      self.completed = true
    end
  end

  def next_step
    roles = user.roles.map(&:downcase)
    steps = if roles.include?('admin')
              %w[create_grades upload_learners send_invites admin_onboarding]
            else
              %w[create_grades upload_learners] # Default flow
            end

    current_index = steps.index(current_step)
    return nil if current_index.nil? || current_index >= steps.size - 1

    steps[current_index + 1]
  end
end
