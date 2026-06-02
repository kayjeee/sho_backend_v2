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

  # ======================== INDEXES ========================
  index({ grade_id: 1 })

  # ===================== VALIDATIONS ======================
  validates :name, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }
end
