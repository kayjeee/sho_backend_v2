# app/models/teacher_grade_assignment.rb
class TeacherGradeAssignment
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :role_type,             type: String, default: 'primary'
  field :status,                type: Integer, default: 0
  field :assigned_at,           type: DateTime
  field :terminated_at,         type: DateTime
  field :termination_reason,    type: String
  field :suspended_at,          type: DateTime
  field :suspension_reason,     type: String

  # ===================== CONSTANTS =======================
  ROLE_TYPES = %w[primary assistant substitute coordinator].freeze
  
  STATUSES = {
    'active' => 0,
    'inactive' => 1,
    'terminated' => 2,
    'suspended' => 3
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :role_type,         presence: true, inclusion: { in: ROLE_TYPES }
  validates :status,            inclusion: { in: STATUSES.values }
  validates :teacher_id,        presence: true
  validates :grade_id,          presence: true
  validates :school_id,         presence: true
  validates :assigned_by_id,    presence: true
  validates :assigned_at,       presence: true

  # Ensure unique assignment per teacher-grade combination
  validates :teacher_id, uniqueness: { scope: [:grade_id, :role_type], message: "already assigned to this grade with this role" }

  # ===================== ASSOCIATIONS =====================
  belongs_to :teacher,          class_name: 'User', inverse_of: :teacher_grade_assignments
  belongs_to :grade,            class_name: 'Grade'
  belongs_to :school,           class_name: 'School'
  belongs_to :assigned_by,      class_name: 'User', inverse_of: :assigned_teacher_roles

  # ======================== INDEXES =======================
  index({ teacher_id: 1, grade_id: 1, role_type: 1 }, { unique: true })
  index({ school_id: 1, status: 1 })
  index({ grade_id: 1, status: 1 })
  index({ teacher_id: 1, status: 1 })
  index({ assigned_at: 1 })

  # ========================= SCOPES ========================
  scope :active,                -> { where(status: 0) }
  scope :inactive,              -> { where(status: 1) }
  scope :terminated,            -> { where(status: 2) }
  scope :suspended,             -> { where(status: 3) }
  scope :by_teacher,            ->(teacher_id) { where(teacher_id: teacher_id) }
  scope :by_grade,              ->(grade_id) { where(grade_id: grade_id) }
  scope :by_school,             ->(school_id) { where(school_id: school_id) }
  scope :by_role_type,          ->(role_type) { where(role_type: role_type) }
  scope :primary_teachers,      -> { where(role_type: 'primary') }
  scope :assistant_teachers,    -> { where(role_type: 'assistant') }

  # ======================== CALLBACKS =======================
  before_validation :set_assigned_at, if: -> { assigned_at.blank? }
  after_create :log_assignment_creation
  after_update :log_assignment_updates

  # ========================= METHODS ========================

  # Status helper methods
  def active?
    status == 0
  end

  def inactive?
    status == 1
  end

  def terminated?
    status == 2
  end

  def suspended?
    status == 3
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  # Role type helpers
  def primary_teacher?
    role_type == 'primary'
  end

  def assistant_teacher?
    role_type == 'assistant'
  end

  def substitute_teacher?
    role_type == 'substitute'
  end

  def coordinator?
    role_type == 'coordinator'
  end

  # Assignment management
  def activate!
    update!(status: 0)
    Rails.logger.info "✅ Teacher assignment activated: #{teacher.name} -> #{grade.name}"
    true
  end

  def deactivate!
    update!(status: 1)
    Rails.logger.info "⏸️ Teacher assignment deactivated: #{teacher.name} -> #{grade.name}"
    true
  end

  def terminate!(reason = nil)
    update!(
      status: 2,
      terminated_at: Time.current,
      termination_reason: reason
    )
    Rails.logger.info "🔚 Teacher assignment terminated: #{teacher.name} -> #{grade.name}"
    true
  end

  def suspend!(reason = nil)
    update!(
      status: 3,
      suspended_at: Time.current,
      suspension_reason: reason
    )
    Rails.logger.info "⏸️ Teacher assignment suspended: #{teacher.name} -> #{grade.name}"
    true
  end

  # Duration calculations
  def assignment_duration_days
    return 0 unless assigned_at
    
    end_date = case status
                when 2 then terminated_at || updated_at
                when 3 then suspended_at || updated_at
                else Time.current
                end
    
    ((end_date - assigned_at) / 1.day).to_i
  end

  def assignment_duration_text
    days = assignment_duration_days
    return "Less than a day" if days < 1
    return "#{days} day#{'s' if days != 1}" if days < 30
    
    months = (days / 30.0).round(1)
    "#{months} month#{'s' if months != 1}"
  end

  # Export methods
  def to_api_hash
    {
      id: id.to_s,
      role_type: role_type,
      status: status,
      status_text: status_text,
      teacher: {
        id: teacher_id.to_s,
        name: teacher&.name,
        email: teacher&.email
      },
      grade: {
        id: grade_id.to_s,
        name: grade&.name,
        grade_level: grade.try(:grade_level) || grade.try(:level)
      },
      school: {
        id: school_id.to_s,
        name: school&.schoolName
      },
      assigned_by: {
        id: assigned_by_id.to_s,
        name: assigned_by&.name
      },
      assigned_at: assigned_at,
      assignment_duration: {
        days: assignment_duration_days,
        text: assignment_duration_text
      },
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def set_assigned_at
    self.assigned_at = Time.current
  end

  def log_assignment_creation
    Rails.logger.info "✅ Teacher assignment created: #{teacher&.name} assigned to #{grade&.name} as #{role_type} by #{assigned_by&.name}"
  end

  def log_assignment_updates
    if saved_change_to_status?
      old_status, new_status = saved_change_to_status
      Rails.logger.info "🔄 Teacher assignment status changed: #{teacher&.name} -> #{grade&.name} from #{STATUSES.key(old_status)} to #{STATUSES.key(new_status)}"
    end

    if saved_change_to_role_type?
      old_role, new_role = saved_change_to_role_type
      Rails.logger.info "🔄 Teacher assignment role changed: #{teacher&.name} -> #{grade&.name} from #{old_role} to #{new_role}"
    end
  end
end
