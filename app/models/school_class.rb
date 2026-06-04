class SchoolClass
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,               type: String
  field :capacity,           type: Integer, default: 40
  field :class_teacher_id,   type: String # Points to Auth0 ID or Teacher reference
  field :subject_teacher_ids, type: Hash,    default: {} # Map: { "subject_id" => "teacher_id" }
  field :learner_ids,        type: Array,   default: [] # Array of Learner ObjectIds

  # ===================== ASSOCIATIONS =====================
  belongs_to :grade, class_name: 'Grade', inverse_of: :school_classes
  has_many :learners, dependent: :nullify

  # ======================== INDEXES ========================
  index({ grade_id: 1 })
  index({ name: 1 })

  # ===================== VALIDATIONS ======================
  validates :name, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validate :capacity_not_exceeded

  # ========================= METHODS =========================

  def current_learners_count
    learner_ids.count
  end

  def available_spots
    capacity - current_learners_count
  end

  def full?
    current_learners_count >= capacity
  end

  def add_learner(learner_id)
    return false if full?
    return false if learner_ids.include?(learner_id)

    add_to_set(learner_ids: learner_id)
  end

  def remove_learner(learner_id)
    pull(learner_ids: learner_id)
  end

  def assign_class_teacher(teacher_id)
    update(class_teacher_id: teacher_id)
  end

  def assign_subject_teacher(subject_id, teacher_id)
    # Reassigning the hash to trigger Mongoid's dirty tracking
    new_hash = subject_teacher_ids.dup
    new_hash[subject_id] = teacher_id
    self.subject_teacher_ids = new_hash
    save
  end

  def remove_subject_teacher(subject_id)
    new_hash = subject_teacher_ids.dup
    new_hash.delete(subject_id)
    self.subject_teacher_ids = new_hash
    save
  end

  def get_subject_teacher(subject_id)
    subject_teacher_ids[subject_id]
  end

  def subject_teachers_summary
    subject_teacher_ids.map do |subject_id, teacher_id|
      { subject_id: subject_id, teacher_id: teacher_id }
    end
  end

  private

  def capacity_not_exceeded
    if learner_ids.count > capacity
      errors.add(:capacity, "cannot be less than current number of learners (#{learner_ids.count})")
    end
  end
end
