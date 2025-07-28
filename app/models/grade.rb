# app/models/grade.rb
class Grade
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name, type: String
  field :level, type: Integer
  field :description, type: String

  # ===================== VALIDATIONS ======================
  validates :name, presence: true, uniqueness: true
  validates :level, presence: true, uniqueness: true

  # ===================== ASSOCIATIONS =====================
  has_many :learners, class_name: 'Learner'
  belongs_to :school, class_name: 'School', optional: true

  # ========================= SCOPES ========================
  scope :by_level, ->(level) { where(level: level) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }

  # ========================= METHODS ========================
  def self.create_default_grades
    grades = [
      { name: 'Grade R', level: 0 },
      { name: 'Grade 1', level: 1 },
      { name: 'Grade 2', level: 2 },
      { name: 'Grade 3', level: 3 },
      { name: 'Grade 4', level: 4 },
      { name: 'Grade 5', level: 5 },
      { name: 'Grade 6', level: 6 },
      { name: 'Grade 7', level: 7 },
      { name: 'Grade 8', level: 8 },
      { name: 'Grade 9', level: 9 },
      { name: 'Grade 10', level: 10 },
      { name: 'Grade 11', level: 11 },
      { name: 'Grade 12', level: 12 }
    ]

    grades.each do |grade_data|
      Grade.find_or_create_by(level: grade_data[:level]) do |grade|
        grade.name = grade_data[:name]
      end
    end
  end

  def to_s
    name
  end
end