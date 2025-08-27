# app/models/user.rb
class User
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,        type: String
  field :email,       type: String
  field :auth0_id,    type: String

  # Status & accounts
  field :status,      type: String, default: 'active'
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []

  # Login / onboarding
  field :last_login,  type: Time
  field :onboarding_status, type: Hash, default: {
    createGrades: false,
    uploadLearners: false,
    sendInvites: false,
    adminOnboardingCompleted: false,
    parentOnboardingCompleted: false,
    guestOnboardingCompleted: false,
    completed: false,
    lastUpdated: nil
  }

  # ======================== ROLES =========================
  ROLES = %w[
    user
    admin
    teacher
    principal
    district_admin
    super_admin
    parent
    student
    guest
  ].freeze

  field :roles, type: Array, default: ['user']

  validates :roles, presence: true
  validate :roles_must_be_valid

  def roles_must_be_valid
    invalid_roles = roles - ROLES
    if invalid_roles.any?
      errors.add(:roles, "Invalid roles: #{invalid_roles.join(', ')}. Allowed roles: #{ROLES.join(', ')}")
    end
  end

  # ===================== VALIDATIONS ======================
  validates :email,    presence: true, uniqueness: true
  validates :auth0_id, presence: true, uniqueness: true

  # ===================== ASSOCIATIONS =====================
  has_many :conversations,                foreign_key: :user_id
  has_many :accounts,                     class_name: 'Account', inverse_of: :user
  has_many :sent_messages,                class_name: 'Message', inverse_of: :sender
  has_many :messages,                     inverse_of: :user
  has_many :received_messages,            class_name: 'Message', inverse_of: :receiver
  has_many :user_school_roles,            class_name: 'UserSchoolRole', inverse_of: :user

  # Grade-related
  has_many :created_grades,               class_name: 'Grade', inverse_of: :created_by
  has_many :created_learners,             class_name: 'Learner', inverse_of: :created_by
  has_many :learner_invitations_sent,     class_name: 'LearnerInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_sent,     class_name: 'TeacherInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_received, class_name: 'TeacherInvitation', inverse_of: :teacher
  has_many :teacher_grade_assignments,    class_name: 'TeacherGradeAssignment', inverse_of: :teacher
  has_many :assigned_teacher_roles,       class_name: 'TeacherGradeAssignment', inverse_of: :assigned_by

  # Schools
  has_and_belongs_to_many :schools, class_name: 'School', inverse_of: :users, validate: false

  # ======================== CALLBACKS =======================
  before_save :log_school_id_changes, if: :school_ids_changed?

  # ========================= METHODS ========================

  # ---- Grade access helpers ----
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

  def can_access_grade?(grade)
    return true if roles.include?('admin')
    return true if created_grades.include?(grade)
    return true if teaching_grades.include?(grade)

    # Check if user is admin in the grade's school
    user_school_roles.find_by(
      school: grade.school,
      role: 'admin',
      status: 0
    ).present?
  end

  def grades_in_school(school)
    return school.grades if roles.include?('admin')

    created_in_school  = created_grades.where(school: school)
    teaching_in_school = teaching_grades.where(school: school)

    Grade.where(:_id.in => (created_in_school.pluck(:id) + teaching_in_school.pluck(:id)).uniq)
  end

  # ---- School association helpers ----
  def add_school(school_id_string)
    Rails.logger.debug "🏫 User#add_school: Attempting to add school '#{school_id_string}' to user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ Invalid school ID format: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ School '#{school_id_string}' not found in DB. Cannot associate."
      errors.add(:schools, "School not found.")
      return false
    end

    if schools.include?(school_to_add)
      Rails.logger.info "✅ School '#{school_id_string}' already associated with user #{id}."
      return true
    end

    schools << school_to_add
    if save
      Rails.logger.info "✅ Successfully associated school '#{school_id_string}' with user #{id}."
      true
    else
      Rails.logger.error "❌ Failed to save after associating school. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def remove_school(school_id_string)
    Rails.logger.debug "➖ User#remove_school: Attempting to remove school '#{school_id_string}' from user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ Invalid school ID format: '#{school_id_string}'."
      return false
    end

    school_to_remove = schools.find_by(_id: school_bson_id)
    unless school_to_remove
      Rails.logger.warn "⚠️ School '#{school_id_string}' not found in user's associations."
      return false
    end

    schools.delete(school_to_remove)
    if save
      Rails.logger.info "🗑️ Successfully removed school '#{school_id_string}' from user #{id}."
      true
    else
      Rails.logger.error "❌ Failed to save after removing school. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  private

  def log_school_id_changes
    old_school_ids, new_school_ids = changes_to_save['school_ids']
    old_school_ids ||= []
    new_school_ids ||= []

    added   = new_school_ids.map(&:to_s) - old_school_ids.map(&:to_s)
    removed = old_school_ids.map(&:to_s) - new_school_ids.map(&:to_s)

    Rails.logger.debug "🔄 User#log_school_id_changes: Updated schools for user #{id}"
    Rails.logger.debug "  ➕ Added: #{added.inspect}"   if added.any?
    Rails.logger.debug "  ➖ Removed: #{removed.inspect}" if removed.any?
  end
end
