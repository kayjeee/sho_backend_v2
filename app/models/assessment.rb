# app/models/assessment.rb
class Assessment
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :school_id,     type: String
  field :grade_id,      type: String
  field :subject_id,    type: String
  field :academic_year, type: String, default: -> { Time.current.year.to_s }
  field :term,          type: Integer
  field :name,          type: String
  field :max_score,     type: Float
  field :date,          type: Date

  has_many :results, class_name: 'Result', dependent: :destroy

  # ===================== VALIDATIONS ======================
  validates :school_id,     presence: true
  validates :grade_id,      presence: true
  validates :subject_id,    presence: true
  validates :academic_year, presence: true
  validates :term,          presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 4 }
  validates :name,          presence: true
  validates :max_score,     presence: true, numericality: { greater_than: 0 }

  # ======================== INDEXES =======================
  index({ school_id: 1, academic_year: 1, term: 1 })
  index({ grade_id: 1, subject_id: 1 })

  # ========================= SCOPES ========================
  scope :by_school,        ->(school_id) { where(school_id: school_id.to_s) }
  scope :by_grade,         ->(grade_id) { where(grade_id: grade_id.to_s) }
  scope :by_subject,       ->(subject_id) { where(subject_id: subject_id.to_s) }
  scope :by_academic_year, ->(year) { where(academic_year: year.to_s) }
  scope :by_term,          ->(term_val) { where(term: term_val.to_i) }

  # ========================= METHODS ========================
  def grade_name
    return nil if grade_id.blank?
    g_str = grade_id.to_s
    g_bson = BSON::ObjectId.legal?(g_str) ? BSON::ObjectId.from_string(g_str) : nil
    Grade.where(:id.in => [g_str, g_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving grade_name for Assessment #{id}: #{e.message}"
    nil
  end

  def subject_name
    return nil if subject_id.blank?
    sub_str = subject_id.to_s
    sub_bson = BSON::ObjectId.legal?(sub_str) ? BSON::ObjectId.from_string(sub_str) : nil
    Subject.where(:id.in => [sub_str, sub_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving subject_name for Assessment #{id}: #{e.message}"
    nil
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      grade_id: grade_id.to_s,
      grade_name: grade_name,
      subject_id: subject_id.to_s,
      subject_name: subject_name,
      academic_year: academic_year.to_s,
      term: term,
      name: name,
      max_score: max_score,
      date: date&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
