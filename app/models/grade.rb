class Grade
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,                  type: String
  field :description,           type: String
  field :grade_level,           type: String # Legacy field compatibility
  field :level,                 type: Integer # New field from user prompt
  field :order,                 type: Integer, default: 0
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
  validates :level,       presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :capacity,    presence: true, numericality: { greater_than: 0 }
  validates :status,      inclusion: { in: STATUSES.values }
  validates :school_id,   presence: true

  # ===================== ASSOCIATIONS =====================
  belongs_to :school, class_name: 'School', inverse_of: :grades

  has_many :learners, class_name: 'Learner', inverse_of: :grade, dependent: :nullify
  has_many :learner_invitations, class_name: 'LearnerInvitation', inverse_of: :grade
  has_many :teacher_grade_assignments, class_name: 'TeacherGradeAssignment', inverse_of: :grade
  has_many :school_classes, class_name: 'SchoolClass', inverse_of: :grade, dependent: :destroy

  # ======================== INDEXES ========================
  index({ school_id: 1, name: 1 }, unique: true)
  index({ status: 1 })
  index({ level: 1 })

  # ========================= METHODS =========================

  # Aggregate Methods
  def total_learners
    school_classes.sum { |c| c.learner_ids.count }
  end

  def all_learners
    Learner.where(:id.in => school_classes.flat_map(&:learner_ids))
  end

  def all_teachers
    teachers = {}

    # Add class teachers
    school_classes.each do |school_class|
      if school_class.class_teacher_id.present?
        teachers[school_class.class_teacher_id] = { role: 'class_teacher', class: school_class.name }
      end
    end

    # Add subject teachers
    school_classes.each do |school_class|
      school_class.subject_teacher_ids.each do |subject_id, teacher_id|
        teachers[teacher_id] ||= { role: 'subject_teacher', subjects: [] }
        teachers[teacher_id][:subjects] << subject_id
      end
    end

    teachers.map { |id, info| { teacher_id: id, **info } }
  end

  def capacity_utilization
    total = total_learners
    total_capacity = school_classes.sum(&:capacity)
    total_capacity.positive? ? (total.to_f / total_capacity * 100).round(1) : 0
  end

  def subjects_offered
    school_classes.flat_map { |c| c.subject_teacher_ids.keys }.uniq
  end

  # Class Management Helpers
  def add_class(attributes)
    school_classes.create(attributes)
  end

  def find_class_by_name(class_name)
    school_classes.find_by(name: class_name)
  end

  def classes_summary
    school_classes.map do |c|
      {
        id: c.id.to_s,
        name: c.name,
        learners_count: c.learner_ids.count,
        capacity: c.capacity,
        utilization: "#{c.learner_ids.count}/#{c.capacity}"
      }
    end
  end

  # Serialization helpers
  def to_api_hash
    {
      id: id.to_s,
      name: name,
      level: level,
      description: description,
      order: order,
      capacity: capacity,
      total_learners: total_learners,
      status: status,
      status_text: STATUSES.key(status),
      stats: {
        total_classes: school_classes.count,
        total_learners: total_learners,
        capacity_utilization: capacity_utilization
      }
    }
  end

  def to_summary_hash
    {
      id: id.to_s,
      name: name,
      level: level,
      status: status
    }
  end
end
