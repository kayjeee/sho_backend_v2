# app/models/onboarding_status.rb
class OnboardingStatus
  include Mongoid::Document
  include Mongoid::Timestamps

  embedded_in :user

  # Fields
  field :current_step, type: String
  field :completed_steps, type: Array, default: []
  field :skipped_steps, type: Array, default: []
  field :completion_percentage, type: Integer, default: 0
  field :total_steps_count, type: Integer, default: 0
  field :started_at, type: Time
  field :completed_at, type: Time
  field :client_metadata, type: Hash, default: {}

  # Boolean flags for specific steps
  field :create_grades, type: Boolean, default: false
  field :upload_learners, type: Boolean, default: false
  field :send_invites, type: Boolean, default: false

  # Role-specific completion flags
  field :admin_onboarding_completed, type: Boolean, default: false
  field :parent_onboarding_completed, type: Boolean, default: false
  field :guest_onboarding_completed, type: Boolean, default: false

  # Overall completion
  field :completed, type: Boolean, default: false

  # Validations
  validates :completion_percentage, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }

  # Callbacks
  before_save :calculate_completion_percentage
  before_save :set_timestamps
  after_initialize :set_defaults

  # FIXED: Proper completion percentage calculation
  def calculate_completion_percentage
    return 100 if completed
    return 0 if total_steps_count.zero?

    # Count actual completed steps from boolean fields
    completed_count = 0
    completed_count += 1 if create_grades
    completed_count += 1 if upload_learners
    completed_count += 1 if send_invites

    # Only count role-specific onboarding if user has that role
    user = self._parent
    if user
      completed_count += 1 if admin_onboarding_completed && user.admin?
      completed_count += 1 if parent_onboarding_completed && user.parent?
      completed_count += 1 if guest_onboarding_completed && user.guest?
    end

    # Calculate percentage (0-100)
    percentage = (completed_count.to_f / total_steps_count * 100).round

    # Cap at 100%
    self.completion_percentage = [percentage, 100].min
  end

  # FIXED: Initialize with proper values
  def set_defaults
    if new_record?
      self.started_at ||= Time.current
      self.client_metadata ||= {}
      self.completed_steps ||= []
      self.skipped_steps ||= []

      # Set total steps based on user roles
      set_total_steps_based_on_user_roles
      set_current_step_based_on_user_roles
    end
  end

  # Add this method to the User model if not present
  def assign_attributes_from_api(attrs)
    return unless attrs.is_a?(Hash)

    attrs.each do |key, value|
      snake_key = key.to_s.underscore
      if respond_to?("#{snake_key}=")
        send("#{snake_key}=", value)
      end
    end
  end

  # Complete a step
  def complete_step!(step_name)
    completed_steps << step_name unless completed_steps.include?(step_name)

    # Set boolean flag if it exists
    step_method = step_name.underscore
    if respond_to?("#{step_method}=")
      send("#{step_method}=", true)
    end

    save
  end

  # Auto-complete if all steps are done
  def auto_complete_if_ready!
    return if completed

    # Mark as completed if all required steps are done
    user = self._parent
    return unless user

    if user.admin? && create_grades && upload_learners && send_invites && admin_onboarding_completed
      mark_completed!
    elsif user.parent? && parent_onboarding_completed
      mark_completed!
    elsif user.guest? && guest_onboarding_completed
      mark_completed!
    end
  end

  # Mark as completed
  def mark_completed!
    self.completed = true
    self.completed_at = Time.current
    self.completion_percentage = 100
    self.current_step = 'completed'
    save
  end

  # NEW: Convert to API-friendly hash format
  def to_api_hash
    {
      id: id.to_s,
      current_step: current_step,
      completed_steps: completed_steps || [],
      skipped_steps: skipped_steps || [],
      completion_percentage: completion_percentage.to_f,
      total_steps_count: total_steps_count.to_i,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      completed: completed || false,
      
      # Step-specific booleans
      create_grades: create_grades || false,
      upload_learners: upload_learners || false,
      send_invites: send_invites || false,
      admin_onboarding_completed: admin_onboarding_completed || false,
      parent_onboarding_completed: parent_onboarding_completed || false,
      guest_onboarding_completed: guest_onboarding_completed || false,
      
      # Client metadata
      client_metadata: client_metadata || {},
      
      # Progress information
      progress: {
        steps_completed: (completed_steps || []).count,
        steps_skipped: (skipped_steps || []).count,
        total_steps: total_steps_count.to_i,
        percentage: completion_percentage.to_f
      },
      
      # Additional useful information
      next_step: next_step,
      is_started: started_at.present?,
      is_completed: completed || false,
      time_to_complete: calculate_time_to_complete,
      
      # Timestamps
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  # NEW: Determine the next step to complete
  def next_step
    return nil if completed
    
    user = self._parent
    return nil unless user
    
    if user.admin?
      return 'create_grades' unless create_grades
      return 'upload_learners' unless upload_learners
      return 'send_invites' unless send_invites
      return 'admin_onboarding' unless admin_onboarding_completed
    elsif user.parent?
      return 'parent_onboarding' unless parent_onboarding_completed
    elsif user.guest?
      return 'guest_onboarding' unless guest_onboarding_completed
    end
    
    nil
  end

  # NEW: Calculate time taken to complete onboarding
  def calculate_time_to_complete
    return nil unless started_at && completed_at
    (completed_at - started_at).to_i
  end

  # NEW: Reset onboarding status
  def reset!(reset_by: nil, reason: nil)
    self.current_step = nil
    self.completed_steps = []
    self.skipped_steps = []
    self.completion_percentage = 0
    self.started_at = Time.current
    self.completed_at = nil
    self.completed = false
    
    # Reset all step booleans
    self.create_grades = false
    self.upload_learners = false
    self.send_invites = false
    self.admin_onboarding_completed = false
    self.parent_onboarding_completed = false
    self.guest_onboarding_completed = false
    
    # Add reset metadata
    self.client_metadata['reset_info'] = {
      reset_by: reset_by,
      reason: reason,
      reset_at: Time.current.iso8601
    }
    
    save
  end

  # NEW: Skip a step with reason
  def skip_step!(step_name, reason: nil)
    skipped_step = {
      step: step_name,
      reason: reason,
      skipped_at: Time.current.iso8601
    }
    
    self.skipped_steps << skipped_step unless skipped_steps.any? { |s| s['step'] == step_name }
    save
  end

  # NEW: Check if a step is completed
  def step_completed?(step_name)
    completed_steps.include?(step_name)
  end

  # NEW: Check if a step is skipped
  def step_skipped?(step_name)
    skipped_steps.any? { |s| s['step'] == step_name }
  end

  # NEW: Get completion status as text
  def status_text
    if completed
      'Completed'
    elsif started_at.present?
      'In Progress'
    else
      'Not Started'
    end
  end

  # NEW: Get percentage as formatted string
  def percentage_formatted
    "#{completion_percentage}%"
  end

  private

  def set_total_steps_based_on_user_roles
    user = self._parent
    return unless user

    if user.admin?
      self.total_steps_count = 4  # create_grades, upload_learners, send_invites, admin_onboarding
    elsif user.parent?
      self.total_steps_count = 1  # parent_onboarding only
    elsif user.guest?
      self.total_steps_count = 1  # guest_onboarding only
    else
      self.total_steps_count = 3  # default steps (create_grades, upload_learners, send_invites)
    end
  end

  def set_current_step_based_on_user_roles
    user = self._parent
    return unless user

    if user.admin?
      self.current_step = 'create_grades' unless current_step.present?
    elsif user.parent?
      self.current_step = 'parent_onboarding' unless current_step.present?
    elsif user.guest?
      self.current_step = 'guest_onboarding' unless current_step.present?
    else
      self.current_step = 'create_grades' unless current_step.present?
    end
  end

  def set_timestamps
    if completed_changed? && completed
      self.completed_at = Time.current
    end
  end
end