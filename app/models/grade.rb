class Grade
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,                  type: String
  field :description,           type: String
  field :grade_level,           type: String
  field :capacity,              type: Integer, default: 30
  field :min_age,               type: Integer
  field :max_age,               type: Integer
  field :status,                type: Integer, default: 0
  field :academic_year_start,   type: Date
  field :academic_year_end,     type: Date
  field :fees,                  type: Float, default: 0.0
  field :curriculum_info,       type: Hash, default: {}
  field :schedule_info,         type: Hash, default: {}

  # ===================== CONSTANTS ========================
  STATUSES = {
    'active' => 0,
    'inactive' => 1,
    'archived' => 2,
    'planning' => 3
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :name,        presence: true, uniqueness: { scope: :school_id }
  validates :grade_level, presence: true
  validates :capacity,    presence: true, numericality: { greater_than: 0 }
  validates :status,      inclusion: { in: STATUSES.values }
  validates :school_id,   presence: true

  # ===================== ASSOCIATIONS =====================
  belongs_to :school, class_name: 'School', inverse_of: :grades

  has_many :learners, class_name: 'Learner', inverse_of: :grade
  has_many :learner_invitations, class_name: 'LearnerInvitation', inverse_of: :grade
  has_many :teacher_grade_assignments, class_name: 'TeacherGradeAssignment', inverse_of: :grade
  has_many :school_classes, class_name: 'SchoolClass', inverse_of: :grade, dependent: :destroy

  # ======================== INDEXES ========================
  index({ school_id: 1, name: 1 }, unique: true)
  index({ school_id: 1, grade_level: 1 })
  index({ status: 1 })
  index({ academic_year_start: 1, academic_year_end: 1 })

  # ========================= SCOPES ========================
  scope :active,                  -> { where(status: 0) }
  scope :inactive,                -> { where(status: 1) }
  scope :archived,                -> { where(status: 2) }
  scope :planning,                -> { where(status: 3) }
  scope :by_school,               ->(school_id) { where(school_id: school_id) }
  scope :by_academic_year,        ->(year) { where(academic_year_start: year.beginning_of_year..year.end_of_year) }
  scope :with_capacity,           -> { where(:capacity.gt => 0) }
  scope :available_for_enrollment, -> {
    active.where('$expr' => { '$lt' => [{ '$size' => '$learner_ids' }, '$capacity'] })
  }

  # ======================== CALLBACKS ========================
  before_validation :set_defaults

  # ========================= METHODS =========================

  # Status helpers
  def active?
    status == STATUSES['active']
  end

  def inactive?
    status == STATUSES['inactive']
  end

  def archived?
    status == STATUSES['archived']
  end

  def planning?
    status == STATUSES['planning']
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  # Enrollment management
  def current_enrollment_count
    learners.active.count
  end

  def available_spots
    [capacity - current_enrollment_count, 0].max
  end

  def full?
    current_enrollment_count >= capacity
  end

  def can_enroll_learner?
    active? && !full?
  end

  # Teacher management
  def assigned_teachers
    user_ids = teacher_grade_assignments.where(status: 0).pluck(:user_id)
    User.where(:id.in => user_ids)
  end

  def primary_teachers
    user_ids = teacher_grade_assignments.where(status: 0, role_type: 'primary').pluck(:user_id)
    User.where(:id.in => user_ids)
  end

  def assistant_teachers
    user_ids = teacher_grade_assignments.where(status: 0, role_type: 'assistant').pluck(:user_id)
    User.where(:id.in => user_ids)
  end

  # Academic year helpers
  def current_academic_year?
    return false unless academic_year_start && academic_year_end

    today = Date.current
    today >= academic_year_start && today <= academic_year_end
  end

  def academic_year_label
    return 'Not Set' unless academic_year_start && academic_year_end

    "#{academic_year_start.year}-#{academic_year_end.year}"
  end

  # Provide aggregate statistics shortcuts
  def total_learners
    school_classes.sum { |c| c.learner_ids.count }
  end

  # Invitation management
  def pending_invitations_count
    learner_invitations.pending.count
  end

  # Serialization helpers
  def to_api_hash
    {
      id: id.to_s,
      name: name,
      description: description,
      grade_level: grade_level,
      capacity: capacity,
      current_enrollment: current_enrollment_count,
      learners_count: current_enrollment_count, # Added at top level
      available_spots: available_spots,
      min_age: min_age,
      max_age: max_age,
      status: status,
      status_text: status_text,
      fees: fees,
      academic_year: {
        start: academic_year_start,
        end: academic_year_end,
        label: academic_year_label,
        is_current: current_academic_year?
      },
      school: {
        id: school_id.to_s,
        name: school&.schoolName || school&.name
      },
      curriculum_info: curriculum_info,
      schedule_info: schedule_info,
      stats: {
        learners_count: current_enrollment_count,
        teachers_count: assigned_teachers.count,
        pending_invitations: pending_invitations_count
      }
    }
  end

  def to_summary_hash
    {
      id: id.to_s,
      name: name,
      grade_level: grade_level,
      capacity: capacity,
      current_enrollment: current_enrollment_count,
      available_spots: available_spots,
      status: status,
      status_text: status_text,
      academic_year_label: academic_year_label
    }
  end

  private

  def set_defaults
    self.curriculum_info ||= {}
    self.schedule_info ||= {}

    if academic_year_start.blank? && academic_year_end.blank?
      current_date = Date.current
      if current_date.month >= 8
        self.academic_year_start = Date.new(current_date.year, 8, 1)
        self.academic_year_end = Date.new(current_date.year + 1, 6, 30)
      else
        self.academic_year_start = Date.new(current_date.year - 1, 8, 1)
        self.academic_year_end = Date.new(current_date.year, 6, 30)
      end
    end
  end
end
