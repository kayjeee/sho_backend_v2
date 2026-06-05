class SchoolClass
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :capacity, type: Integer, default: 40
  field :class_teacher_id, type: String
  field :subject_teacher_ids, type: Hash, default: {}
  field :learner_ids, type: Array, default: []

  belongs_to :grade, class_name: 'Grade', inverse_of: :school_classes
  has_many :learners, class_name: 'Learner', inverse_of: :school_class, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :grade_id }
  validates :capacity, presence: true, numericality: { greater_than: 0, only_integer: true }
  validate :capacity_not_exceeded

  index({ grade_id: 1, name: 1 }, { unique: true })
  index({ name: 1 })

  # Instance Methods
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

    learner_ids << learner_id
    save
  end

  def remove_learner(learner_id)
    learner_ids.delete(learner_id)
    save
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

  def class_teacher
    # Fetch teacher details from User service or Auth0
    # Return teacher object or ID
    class_teacher_id
  end

  def subject_teachers_summary
    subject_teacher_ids.map do |subject_id, teacher_id|
      { subject_id: subject_id, teacher_id: teacher_id }
    end
  end

  private

  def capacity_not_exceeded
    # Use learner_ids_changed? or just check count if it's during save
    if learner_ids.count > capacity
      errors.add(:capacity, "cannot be less than current number of learners (#{learner_ids.count})")
    end
  end

  def learner_belongs_to_grade
    # Ensure all learners belong to the same grade
    # Implement if needed
  end
end
