# frozen_string_literal: true
# app/models/user.rb
# Complete model with onboarding integration and last seen tracking

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
  field :last_seen_at,     type: Time

  field :phone,            type: String
  field :phone_number,     type: String
  field :invited_via,      type: String
  field :accepted_at,      type: Time

  # ======================== ONBOARDING SYNC FIELDS ========================
  # These are denormalized from OnboardingStatus for efficient querying
  # Updated by OnboardingStatus#sync_to_user callback
  field :onboarding_completed, type: Boolean, default: false
  field :onboarding_progress,  type: Float,   default: 0.0

  # ===================== VALIDATIONS ======================
  validates :email,
            presence: true,
            uniqueness: true

  validates :auth0_id,
            presence: true,
            uniqueness: true

  # ===================== ASSOCIATIONS =====================
  has_many :conversations,
           foreign_key: :user_id

  has_many :accounts,
           class_name: 'Account',
           inverse_of: :user

  has_many :sent_messages,
           class_name: 'Message',
           inverse_of: :sender,
           primary_key: :id,
           foreign_key: :sender_id

  has_many :received_messages,
           class_name: 'Message',
           inverse_of: :receiver,
           primary_key: :id,
           foreign_key: :receiver_id

  has_many :user_school_roles,
           class_name: 'UserSchoolRole',
           inverse_of: :user

  has_many :teacher_grade_assignments,
           class_name: 'TeacherGradeAssignment',
           inverse_of: :teacher

  has_many :assigned_teacher_roles,
           class_name: 'TeacherGradeAssignment',
           inverse_of: :assigned_by

  # ===================== GRADE ASSOCIATIONS =====================
  has_many :created_grades,
           class_name: 'Grade',
           inverse_of: :created_by

  has_many :created_learners,
           class_name: 'Learner',
           inverse_of: :created_by

  has_many :learner_invitations_sent,
           class_name: 'LearnerInvitation',
           inverse_of: :invited_by

  has_many :teacher_invitations_sent,
           class_name: 'TeacherInvitation',
           inverse_of: :invited_by

  has_many :teacher_invitations_received,
           class_name: 'TeacherInvitation',
           inverse_of: :teacher

  has_and_belongs_to_many :schools,
                          class_name: 'School',
                          inverse_of: :users,
                          validate: false

  has_one :teacher_profile,
          class_name: 'Teacher',
          inverse_of: :user

  # ===================== ONBOARDING =====================
  embeds_one :onboarding_status,
             class_name: 'OnboardingStatus',
             inverse_of: :user

  # ======================= INDEXES ========================
  index({ email: 1 }, { unique: true })
  index({ auth0_id: 1 }, { unique: true })

  index({ roles: 1 })
  index({ status: 1 })

  index({ last_login: 1 })
  index({ last_seen_at: 1 })

  # Onboarding-related indexes
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

  # ===================== GRADE METHODS =====================

  def teaching_grades
    Grade.joins(:teacher_grade_assignments)
         .where(
           teacher_grade_assignments: {
             teacher_id: id,
             status: 0
           }
         )
  end

  def primary_teaching_grades
    teaching_grades.where(
      teacher_grade_assignments: {
        role_type: 'primary'
      }
    )
  end

  def assistant_teaching_grades
    teaching_grades.where(
      teacher_grade_assignments: {
        role_type: 'assistant'
      }
    )
  end

  def teacher_slug(_school_name = nil)
    base = name.to_s
               .downcase
               .gsub(/\s+/, '-')
               .gsub(/[^a-z0-9-]/, '')

    short_id = id.to_s.last(4)

    "#{base}-#{short_id}"
  end

  def can_access_grade?(grade)
    return true if roles.include?('Admin')
    return true if created_grades.include?(grade)
    return true if teaching_grades.include?(grade)

    user_school_roles.find_by(
      school: grade.school,
      role: 'Admin',
      status: 0
    ).present?
  end

  def grades_in_school(school)
    return school.grades if roles.include?('Admin')

    created_in_school = created_grades.where(school: school)
    teaching_in_school = teaching_grades.where(school: school)

    Grade.where(
      :_id.in => (
        created_in_school.pluck(:id) +
        teaching_in_school.pluck(:id)
      ).uniq
    )
  end

  # ================== SCHOOL MANAGEMENT ==================

  def add_school(school_id_string)
    Rails.logger.debug "🏫 User#add_school: Attempting to add school #{school_id_string} to user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(
        school_id_string.to_s.strip
      )
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ Invalid BSON::ObjectId: #{school_id_string}"
      errors.add(:schools, 'Invalid school ID format.')
      return false
    end

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ School not found: #{school_id_string}"
      errors.add(:schools, 'School not found.')
      return false
    end

    if schools.include?(school_to_add)
      Rails.logger.info "✅ School already associated"
      return true
    end

    schools << school_to_add

    if save
      Rails.logger.info "✅ School added successfully"
      true
    else
      Rails.logger.error "❌ Failed to save user: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def remove_school(school_id_string)
    Rails.logger.debug "➖ Removing school #{school_id_string} from user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(
        school_id_string.to_s.strip
      )
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ Invalid BSON::ObjectId: #{school_id_string}"
      errors.add(:schools, 'Invalid school ID format.')
      return false
    end

    school_to_remove = schools.find_by(_id: school_bson_id)

    unless school_to_remove
      Rails.logger.warn "⚠️ School not associated with user"
      return false
    end

    schools.delete(school_to_remove)

    if save
      Rails.logger.info "🗑️ School removed successfully"
      true
    else
      Rails.logger.error "❌ Failed to save user: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # ================== ONBOARDING ==================

  def ensure_onboarding_status
    build_onboarding_status unless onboarding_status
  end

  def initialize_onboarding_status
    return if onboarding_status&.persisted?

    ensure_onboarding_status

    configure_initial_onboarding_state

    onboarding_status.save!

    Rails.logger.info "🆕 Initialized onboarding status for #{auth0_id}"
  end

  def configure_initial_onboarding_state
    user_roles = roles || []
    onboarding = onboarding_status

    case
    when user_roles.include?('admin')
      onboarding.current_step = 'create_grades'
      onboarding.total_steps_count = 4

    when user_roles.include?('parent')
      onboarding.current_step = 'PROFILE_SETUP'
      onboarding.total_steps_count = 8

    when user_roles.include?('guest')
      onboarding.current_step = 'guest_onboarding'
      onboarding.total_steps_count = 1

    else
      onboarding.current_step = 'create_grades'
      onboarding.total_steps_count = 3
    end

    onboarding.client_metadata = {
      'initialized_at' => Time.current.iso8601,
      'user_roles' => user_roles,
      'initialization_context' => determine_initialization_context
    }
  end

  def determine_initialization_context
    if schools.any?
      'existing_school_association'
    elsif created_at > 1.hour.ago
      'new_user_registration'
    else
      'retroactive_initialization'
    end
  end

  def update_onboarding_status!(attrs = {})
    ensure_onboarding_status

    begin
      if attrs.is_a?(Hash) &&
         attrs.keys.any? { |k| k.to_s.include?('_') }

        onboarding_status.assign_attributes(attrs)
      else
        onboarding_status.assign_attributes_from_api(attrs)
      end

      onboarding_status.auto_complete_if_ready!
      onboarding_status.save!

      Rails.logger.info "🔄 Updated onboarding status for #{auth0_id}"

      onboarding_status
    rescue => e
      Rails.logger.error "❌ Failed onboarding update: #{e.message}"
      raise e
    end
  end

  def needs_onboarding?
    !onboarding_completed
  end

  def onboarding_progress
    read_attribute(:onboarding_progress) || 0.0
  end

  def can_access_main_features?
    return true unless needs_onboarding?

    ensure_onboarding_status

    critical_steps_completed =
      onboarding_status.create_grades &&
      onboarding_status.upload_learners

    role_onboarding_completed =
      onboarding_status.admin_onboarding_completed ||
      onboarding_status.parent_onboarding_completed ||
      onboarding_status.guest_onboarding_completed

    critical_steps_completed || role_onboarding_completed
  end

  def current_onboarding_step
    ensure_onboarding_status
    onboarding_status.current_step
  end

  # ================== LAST SEEN TRACKING ==================

  # Stamps the current time as the user's last activity.
  # Called by UsersController#heartbeat and the API request tracker.
  def touch_last_seen!
    set(last_seen_at: Time.current)
  end

  def online?
    last_seen_at.present? && last_seen_at > 5.minutes.ago
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
    roles.delete(role.to_s)
    save
  end

  def display_name
    name.presence || email.split('@').first
  end

  def to_api_hash
    base_hash = {
      id: id.to_s,
      auth0_id: auth0_id,
      name: name,
      email: email,
      roles: roles,
      school_ids: school_ids&.map(&:to_s),
      status: status,
      last_login: last_login&.iso8601,
      last_seen_at: last_seen_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }

    ensure_onboarding_status

    base_hash[:onboardingStatus] = onboarding_status.to_api_hash
    base_hash[:needsOnboarding] = needs_onboarding?
    base_hash[:canAccessMainFeatures] = can_access_main_features?
    base_hash[:onboardingProgress] = onboarding_progress

    base_hash
  end

  # ==================== CLASS METHODS ====================

  def self.bulk_update_onboarding_status(user_ids, updates)
    results = {
      success: [],
      failed: []
    }

    User.in(id: user_ids).each do |user|
      begin
        user.update_onboarding_status!(updates)
        results[:success] << user.auth0_id
      rescue => e
        results[:failed] << {
          user_id: user.auth0_id,
          error: e.message
        }
      end
    end

    results
  end

  def self.by_onboarding_status(status)
    case status.to_s
    when 'completed'
      where(onboarding_completed: true)

    when 'in_progress'
      where(
        onboarding_completed: false,
        'onboarding_status.started_at'.ne => nil
      )

    when 'not_started'
      where('onboarding_status.started_at' => nil)

    when 'needs_attention'
      cutoff_date = 7.days.ago

      where(
        onboarding_completed: false,
        'onboarding_status.started_at'.lt => cutoff_date
      )

    else
      all
    end
  end

  def self.onboarding_statistics
    total_users = count

    completed_users =
      where(onboarding_completed: true).count

    in_progress_users =
      where(
        onboarding_completed: false,
        'onboarding_status.started_at'.ne => nil
      ).count

    not_started_users =
      where('onboarding_status.started_at' => nil).count

    {
      total_users: total_users,
      completed_users: completed_users,
      in_progress_users: in_progress_users,
      not_started_users: not_started_users,
      completion_rate:
        total_users > 0 ?
        (completed_users.to_f / total_users * 100).round(2) :
        0,
      average_completion_percentage:
        calculate_average_completion_percentage
    }
  end

  def self.calculate_average_completion_percentage
    users_with_progress =
      where(:onboarding_progress.ne => nil)

    return 0 if users_with_progress.count.zero?

    total_percentage =
      users_with_progress.sum(:onboarding_progress)

    (total_percentage / users_with_progress.count).round(2)
  end

  private

  def normalize_roles
    return unless roles_changed?

    self.roles =
      Array(roles)
      .map { |r| r.to_s.downcase.strip }
      .uniq
      .compact
  end

  def log_school_id_changes
    old_school_ids, new_school_ids =
      changes['school_ids']

    old_school_ids ||= []
    new_school_ids ||= []

    old_school_ids_str = old_school_ids.map(&:to_s)
    new_school_ids_str = new_school_ids.map(&:to_s)

    added = new_school_ids_str - old_school_ids_str
    removed = old_school_ids_str - new_school_ids_str

    Rails.logger.debug "🔄 School IDs updated for user #{id}"
    Rails.logger.debug "OLD: #{old_school_ids_str.inspect}"
    Rails.logger.debug "NEW: #{new_school_ids_str.inspect}"

    Rails.logger.debug "➕ Added: #{added.inspect}" if added.any?
    Rails.logger.debug "➖ Removed: #{removed.inspect}" if removed.any?
  end
end
