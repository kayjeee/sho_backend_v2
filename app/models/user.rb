# frozen_string_literal: true
# app/models/user.rb - Complete model with onboarding integration and FIXED fields

class User
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,             type: String               
  field :email,            type: String               
  field :auth0_id,         type: String               
  field :roles,            type: Array,  default: []   
  field :cash_account,     type: Float,  default: 0.0  
  field :payment_history,  type: Array,  default: []   
  field :status,           type: String, default: 'active'
  field :last_login,       type: Time
  field :phone,            type: String
  field :phone_number,     type: String

  # ======================== NEW: ONBOARDING SYNC FIELDS ========================
  # These are denormalized from OnboardingStatus for efficient querying
  # Updated by OnboardingStatus#sync_to_user callback
  field :onboarding_completed,  type: Boolean, default: false
  field :onboarding_progress,   type: Float,   default: 0.0
  # ==============================================================================

  # ===================== VALIDATIONS ======================
  validates :email,        presence: true, uniqueness: true
  validates :auth0_id,     presence: true, uniqueness: true

  # ===================== ASSOCIATIONS =====================
  has_many :conversations,       foreign_key: :user_id
  has_many :accounts,            class_name: 'Account', inverse_of: :user
  has_many :sent_messages,       class_name: 'Message', inverse_of: :sender
  has_many :messages,            inverse_of: :user
  has_many :received_messages,   class_name: 'Message', inverse_of: :receiver
  has_many :user_school_roles,   class_name: 'UserSchoolRole', inverse_of: :user

  # GRADE-RELATED ASSOCIATIONS
  has_many :created_grades,      class_name: 'Grade', inverse_of: :created_by
  has_many :created_learners,    class_name: 'Learner', inverse_of: :created_by
  has_many :learner_invitations_sent, class_name: 'LearnerInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_sent, class_name: 'TeacherInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_received, class_name: 'TeacherInvitation', inverse_of: :teacher
  has_many :teacher_grade_assignments, class_name: 'TeacherGradeAssignment', inverse_of: :teacher
  has_many :assigned_teacher_roles, class_name: 'TeacherGradeAssignment', inverse_of: :assigned_by

  has_and_belongs_to_many :schools, class_name: 'School', inverse_of: :users, validate: false

  # ONBOARDING ASSOCIATION
  embeds_one :onboarding_status, class_name: 'OnboardingStatus', inverse_of: :user

  # ======================= INDEXES ========================
  index({ email: 1 }, { unique: true })
  index({ auth0_id: 1 }, { unique: true })
  index({ roles: 1 })
  index({ status: 1 })
  index({ last_login: 1 })
  
  # Onboarding-related indexes (denormalized fields for fast queries)
  index({ onboarding_completed: 1 })
  index({ onboarding_progress: 1 })
  
  # Embedded document indexes
  index({ 'onboarding_status.completed_steps' => 1 })
  index({ 'onboarding_status.current_step' => 1 })
  index({ 'onboarding_status.completion_percentage' => 1 })

  # ======================== CALLBACKS =======================
  before_save :normalize_roles
  before_save :log_school_id_changes, if: :school_ids_changed?
  
  # Onboarding callbacks
  after_initialize :ensure_onboarding_status
  after_create :initialize_onboarding_status

  # ======================== SCOPES ========================
  scope :active, -> { where(status: 'active') }
  scope :with_role, ->(role) { where(roles: role) }
  scope :admins, -> { where(roles: 'admin') }
  scope :parents, -> { where(roles: 'parent') }
  scope :guests, -> { where(roles: 'guest') }

  # ===================== GRADE-RELATED METHODS =====================

  def teaching_grades
    Grade.joins(:teacher_grade_assignments)
         .where(teacher_grade_assignments: { teacher_id: id, status: 0 })
  end

  def primary_teaching_grades
    teaching_grades.where(teacher_grade_assignments: { role_type: 'primary' })
  end

  def assistant_teaching_grades
    teaching_grades.where(teacher_grade_assignments: { role_type: 'assistant' })
  end

  def teacher_slug(school_name = nil)
    base = name.to_s.downcase.gsub(/\s+/, '-').gsub(/[^a-z0-9-]/, '')
    short_id = id.to_s.last(4)
    "#{base}-#{short_id}"
  end

  def can_access_grade?(grade)
    return true if roles.include?('Admin')
    return true if created_grades.include?(grade)
    return true if teaching_grades.include?(grade)
    
    # Check if user is admin in the grade's school
    user_school_roles.find_by(
      school: grade.school,
      role: 'Admin',
      status: 0
    ).present?
  end

  def grades_in_school(school)
    return school.grades if roles.include?('Admin')
    
    # Return grades user created or teaches in this school
    created_in_school = created_grades.where(school: school)
    teaching_in_school = teaching_grades.where(school: school)
    
    Grade.where(:_id.in => (created_in_school.pluck(:id) + teaching_in_school.pluck(:id)).uniq)
  end

  # ================== SCHOOL MANAGEMENT METHODS ==================

  def add_school(school_id_string)
    Rails.logger.debug "🏫 User#add_school: Attempting to add school with ID string '#{school_id_string}' to user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#add_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ User#add_school: School with ID '#{school_id_string}' not found in database. Cannot associate."
      errors.add(:schools, "School not found.")
      return false
    end

    if self.schools.include?(school_to_add)
      Rails.logger.info "✅ User#add_school: School '#{school_id_string}' is already associated with user #{id}. No action taken."
      return true
    end

    self.schools << school_to_add

    if save
      Rails.logger.info "✅ User#add_school: Successfully associated school '#{school_id_string}' with user #{id}."
      true
    else
      Rails.logger.error "❌ User#add_school: Failed to save user #{id} after associating school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def remove_school(school_id_string)
    Rails.logger.debug "➖ User#remove_school: Attempting to remove school with ID string '#{school_id_string}' from user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#remove_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_remove = self.schools.find_by(_id: school_bson_id)

    unless school_to_remove
      Rails.logger.warn "⚠️ User#remove_school: School with ID '#{school_id_string}' not found in user's associations for user #{id}."
      return false
    end

    self.schools.delete(school_to_remove)

    if save
      Rails.logger.info "🗑️ User#remove_school: Successfully removed school '#{school_id_string}' from user #{id}."
      true
    else
      Rails.logger.error "❌ User#remove_school: Failed to save user #{id} after removing school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # ================== ONBOARDING MANAGEMENT METHODS ==================

  # Ensure onboarding status exists (lazy initialization)
  def ensure_onboarding_status
    build_onboarding_status unless onboarding_status
  end

  # Initialize onboarding status for new users
  def initialize_onboarding_status
    return if onboarding_status&.persisted?
    
    ensure_onboarding_status
    
    # Set initial configuration based on user roles
    configure_initial_onboarding_state
    
    onboarding_status.save!
    Rails.logger.info "🆕 Initialized onboarding status for new user #{auth0_id}"
  end

  # Configure initial onboarding state based on user roles and context
  def configure_initial_onboarding_state
    user_roles = roles || []
    onboarding = onboarding_status
    
    # Set current step based on primary role
    case
    when user_roles.include?('admin')
      onboarding.current_step = 'create_grades'
      onboarding.total_steps_count = 4 # create_grades, upload_learners, send_invites, admin_onboarding
    when user_roles.include?('parent')
      # For parents, start with first parent step
      onboarding.current_step = 'PROFILE_SETUP'
      onboarding.total_steps_count = 8 # All PARENT_STEPS
    when user_roles.include?('guest')
      onboarding.current_step = 'guest_onboarding'
      onboarding.total_steps_count = 1 # Only guest-specific onboarding
    else
      onboarding.current_step = 'create_grades'
      onboarding.total_steps_count = 3 # Default steps without role-specific
    end
    
    # Set client metadata for tracking
    onboarding.client_metadata = {
      'initialized_at' => Time.current.iso8601,
      'user_roles' => user_roles,
      'initialization_context' => determine_initialization_context
    }
  end

  # Determine the context in which onboarding was initialized
  def determine_initialization_context
    # This can be enhanced based on how users are created in your system
    if schools.any?
      'existing_school_association'
    elsif created_at > 1.hour.ago
      'new_user_registration'
    else
      'retroactive_initialization'
    end
  end

  # Convenience method to update onboarding status with error handling
  def update_onboarding_status!(attrs = {})
    ensure_onboarding_status
    
    begin
      if attrs.is_a?(Hash) && attrs.keys.any? { |k| k.to_s.include?('_') }
        # Handle snake_case input
        onboarding_status.assign_attributes(attrs)
      else
        # Handle camelCase input from API
        onboarding_status.assign_attributes_from_api(attrs)
      end
      
      onboarding_status.auto_complete_if_ready!
      onboarding_status.save!
      
      Rails.logger.info "🔄 Updated onboarding status for user #{auth0_id}"
      onboarding_status
      
    rescue => e
      Rails.logger.error "❌ Failed to update onboarding status for user #{auth0_id}: #{e.message}"
      raise e
    end
  end

  # Check if user needs onboarding
  def needs_onboarding?
    # Use the denormalized field for fast access
    !onboarding_completed
  end

  # Get onboarding progress percentage
  def onboarding_progress
    # Use the denormalized field for fast access
    read_attribute(:onboarding_progress) || 0.0
  end

  # Check if user can access main application features
  def can_access_main_features?
    return true unless needs_onboarding?
    
    # Allow access if user has completed critical steps
    ensure_onboarding_status
    critical_steps_completed = onboarding_status.create_grades && onboarding_status.upload_learners
    
    # Or if user has role-specific onboarding completed
    role_onboarding_completed = onboarding_status.admin_onboarding_completed ||
                               onboarding_status.parent_onboarding_completed ||
                               onboarding_status.guest_onboarding_completed
    
    critical_steps_completed || role_onboarding_completed
  end

  # Get current onboarding step
  def current_onboarding_step
    ensure_onboarding_status
    onboarding_status.current_step
  end

  # Complete a specific onboarding step with comprehensive error handling
  def complete_onboarding_step!(step_name, metadata: {})
    ensure_onboarding_status
    
    begin
      # Store completion metadata
      onboarding_status.client_metadata["#{step_name}_completed_at"] = Time.current.iso8601
      onboarding_status.client_metadata["#{step_name}_metadata"] = metadata if metadata.any?
      
      onboarding_status.complete_step!(step_name)
      
      # Trigger any post-completion actions
      handle_step_completion(step_name, metadata)
      
      Rails.logger.info "✅ User #{auth0_id} completed onboarding step: #{step_name}"
      
    rescue => e
      Rails.logger.error "❌ Failed to complete step #{step_name} for user #{auth0_id}: #{e.message}"
      raise e
    end
  end

  # Skip an onboarding step with reason tracking
  def skip_onboarding_step!(step_name, reason: nil, metadata: {})
    ensure_onboarding_status
    
    begin
      # Store skip metadata
      skip_data = {
        'reason' => reason,
        'skipped_at' => Time.current.iso8601,
        'metadata' => metadata
      }
      
      onboarding_status.client_metadata["#{step_name}_skipped"] = skip_data
      onboarding_status.skip_step!(step_name, reason: reason)
      
      Rails.logger.info "⏭️ User #{auth0_id} skipped onboarding step: #{step_name} (#{reason})"
      
    rescue => e
      Rails.logger.error "❌ Failed to skip step #{step_name} for user #{auth0_id}: #{e.message}"
      raise e
    end
  end

  # Reset onboarding status with audit trail
  def reset_onboarding!(reset_by: nil, reason: nil)
    ensure_onboarding_status
    
    begin
      # Store reset metadata
      onboarding_status.client_metadata['reset_by'] = reset_by
      onboarding_status.client_metadata['reset_reason'] = reason
      onboarding_status.client_metadata['reset_at'] = Time.current.iso8601
      
      onboarding_status.reset!
      
      Rails.logger.info "🔄 Onboarding reset for user #{auth0_id} by #{reset_by || 'system'}"
      
    rescue => e
      Rails.logger.error "❌ Failed to reset onboarding for user #{auth0_id}: #{e.message}"
      raise e
    end
  end

  # Get onboarding analytics data
  def onboarding_analytics
    ensure_onboarding_status
    
    {
      user_id: auth0_id,
      completion_percentage: onboarding_status.completion_percentage,
      steps_completed: onboarding_status.steps_completed_count,
      total_steps: onboarding_status.total_steps_count,
      current_step: onboarding_status.current_step,
      started_at: onboarding_status.started_at,
      completed_at: onboarding_status.completed_at,
      time_to_complete: calculate_time_to_complete,
      skipped_steps: onboarding_status.skipped_steps,
      user_roles: roles,
      school_count: schools.count,
      created_grades_count: created_grades.count,
      created_learners_count: created_learners.count
    }
  end

  # Calculate time taken to complete onboarding
  def calculate_time_to_complete
    return nil unless onboarding_status&.started_at && onboarding_status&.completed_at
    
    duration_seconds = onboarding_status.completed_at - onboarding_status.started_at
    
    {
      seconds: duration_seconds.to_i,
      minutes: (duration_seconds / 60).to_i,
      hours: (duration_seconds / 3600).to_i,
      days: (duration_seconds / 86400).to_i,
      human_readable: ActionController::Base.helpers.distance_of_time_in_words(
        onboarding_status.started_at, 
        onboarding_status.completed_at
      )
    }
  end

  # Enhanced API serialization including onboarding status
  def to_api_hash
    base_hash = {
      auth0_id: auth0_id,
      name: name,
      email: email,
      roles: roles,
      school_ids: school_ids&.map(&:to_s),
      status: status,
      last_login: last_login&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
    
    # Include onboarding status
    ensure_onboarding_status
    base_hash[:onboardingStatus] = onboarding_status.to_api_hash
    
    # Include onboarding-related flags (using denormalized fields)
    base_hash[:needsOnboarding] = needs_onboarding?
    base_hash[:canAccessMainFeatures] = can_access_main_features?
    base_hash[:onboardingProgress] = onboarding_progress
    
    base_hash
  end

  # ================== CLASS METHODS FOR BULK OPERATIONS ==================

  # Bulk onboarding operations for admin users
  def self.bulk_update_onboarding_status(user_ids, updates)
    results = { success: [], failed: [] }
    
    User.in(id: user_ids).each do |user|
      begin
        user.update_onboarding_status!(updates)
        results[:success] << user.auth0_id
      rescue => e
        results[:failed] << { user_id: user.auth0_id, error: e.message }
      end
    end
    
    results
  end

  # Get users by onboarding status for admin dashboards
  def self.by_onboarding_status(status)
    case status.to_s
    when 'completed'
      # Use denormalized field for fast query
      where(onboarding_completed: true)
    when 'in_progress'
      # Use denormalized field + embedded field
      where(onboarding_completed: false, 'onboarding_status.started_at'.ne => nil)
    when 'not_started'
      where('onboarding_status.started_at' => nil)
    when 'needs_attention'
      # Users who started onboarding more than 7 days ago but haven't completed
      cutoff_date = 7.days.ago
      where(
        onboarding_completed: false,
        'onboarding_status.started_at'.lt => cutoff_date
      )
    else
      all
    end
  end

  # Get onboarding completion statistics
  def self.onboarding_statistics
    total_users = count
    # Use denormalized field for fast count
    completed_users = where(onboarding_completed: true).count
    in_progress_users = where(
      onboarding_completed: false,
      'onboarding_status.started_at'.ne => nil
    ).count
    not_started_users = where('onboarding_status.started_at' => nil).count
    
    {
      total_users: total_users,
      completed_users: completed_users,
      in_progress_users: in_progress_users,
      not_started_users: not_started_users,
      completion_rate: total_users > 0 ? (completed_users.to_f / total_users * 100).round(2) : 0,
      average_completion_percentage: calculate_average_completion_percentage
    }
  end

  def self.calculate_average_completion_percentage
    # Use denormalized field for fast aggregation
    users_with_progress = where(:onboarding_progress.ne => nil)
    return 0 if users_with_progress.count == 0
    
    total_percentage = users_with_progress.sum(:onboarding_progress)
    (total_percentage / users_with_progress.count).round(2)
  end

  # ==================== UTILITY METHODS ====================

  def admin?
    roles.include?('admin')
  end

  def parent?
    roles.include?('parent')
  end

  def guest?
    roles.include?('guest')
  end

  def has_role?(role)
    roles.include?(role.to_s)
  end

  def add_role(role)
    return if has_role?(role)
    self.roles << role.to_s
    save
  end

  def remove_role(role)
    self.roles.delete(role.to_s)
    save
  end

  def display_name
    name.presence || email.split('@').first
  end

  private

  def normalize_roles
    self.roles = Array(roles).map { |r| r.to_s.downcase.strip }.uniq.compact if roles_changed?
  end

  def log_school_id_changes
    old_school_ids, new_school_ids = changes_to_save['school_ids']

    old_school_ids = old_school_ids || []
    new_school_ids = new_school_ids || []

    old_school_ids_str = old_school_ids.map(&:to_s)
    new_school_ids_str = new_school_ids.map(&:to_s)

    added   = new_school_ids_str - old_school_ids_str
    removed = old_school_ids_str - new_school_ids_str

    Rails.logger.debug "🔄 User#log_school_id_changes: Associated schools updated for user #{id}:"
    Rails.logger.debug "  OLD (IDs): #{old_school_ids_str.inspect}"
    Rails.logger.debug "  NEW (IDs): #{new_school_ids_str.inspect}"
    Rails.logger.debug "  ➕ ADDED (IDs): #{added.inspect}"   if added.any?
    Rails.logger.debug "  ➖ REMOVED (IDs): #{removed.inspect}" if removed.any?
  end

  # Handle post-step completion actions
  def handle_step_completion(step_name, metadata)
    case step_name.to_s
    when 'create_grades'
      Rails.logger.info "🎯 User #{auth0_id} completed grade creation"
      # Could trigger analytics event, send notification, etc.
      # NotificationService.send_step_completion_notification(self, 'create_grades')
      
    when 'upload_learners'
      Rails.logger.info "👥 User #{auth0_id} completed learner upload"
      learner_count = metadata[:learners_uploaded] || created_learners.count
      Rails.logger.info "📊 Uploaded #{learner_count} learners"
      
    when 'send_invites'
      Rails.logger.info "📧 User #{auth0_id} completed invite sending"
      invite_count = metadata[:invites_sent] || 0
      Rails.logger.info "📊 Sent #{invite_count} invitations"
      
    when 'admin_onboarding'
      Rails.logger.info "👑 User #{auth0_id} completed admin onboarding"
      # AdminOnboardingCompletionJob.perform_async(id)
      
    when 'parent_onboarding'
      Rails.logger.info "👨‍👩‍👧‍👦 User #{auth0_id} completed parent onboarding"
      
    when 'guest_onboarding'
      Rails.logger.info "👤 User #{auth0_id} completed guest onboarding"
    end
    
    # Trigger general step completion analytics
    # AnalyticsService.track_onboarding_step_completion(self, step_name, metadata)
  end
end