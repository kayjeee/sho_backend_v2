class Grade
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :level, type: Integer
  field :description, type: String
  field :order, type: Integer, default: 0

  belongs_to :school
  has_many :school_classes, class_name: 'SchoolClass', dependent: :destroy
  has_many :learners, dependent: :nullify

  validates :name, presence: true
  validates :level, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Aggregate Methods
  def total_learners
    school_classes.sum { |c| c.learner_ids.count }
  end

  def all_learners
    # 1. Learners directly associated with this grade via gradeId
    # 2. Learners associated via classes
    ids = school_classes.flat_map(&:learner_ids).map(&:to_s)

    gid_str = id.to_s
    gid_bson = BSON::ObjectId.legal?(gid_str) ? BSON::ObjectId.from_string(gid_str) : nil
    gid_array = [gid_str, gid_bson].compact

    query = {
      "$or" => [
        { "gradeId" => { "$in" => gid_array } },
        { "grade_id" => { "$in" => gid_array } },
        { "_id" => { "$in" => ids.map { |i| BSON::ObjectId.legal?(i) ? BSON::ObjectId.from_string(i) : i } } }
      ]
    }

    raw_docs = Learner.collection.find(query)
    raw_docs.map { |doc| Learner.instantiate(doc) }
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
    capacity = school_classes.sum(&:capacity)
    capacity.positive? ? (total.to_f / capacity * 100).round(1) : 0
  end

  def subjects_offered
    school_classes.flat_map(&:subject_teacher_ids).map(&:first).uniq
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

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      name: name,
      level: level || 0,
      description: description,
      order: order,
      total_learners: total_learners,
      stats: {
        total_classes: school_classes.count,
        total_learners: total_learners,
        capacity_utilization: capacity_utilization
      }
    }
  end
end
