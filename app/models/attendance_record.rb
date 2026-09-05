# app/models/attendance_record.rb
class AttendanceRecord
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :school_id,       type: String
  field :grade_id,        type: String
  field :school_class_id, type: String
  field :learner_id,      type: String
  field :date,            type: Date
  field :status,          type: Integer
  field :recorded_by_id,  type: String
  field :note,            type: String

  # ===================== CONSTANTS =======================
  STATUSES = {
    'present' => 0,
    'absent'  => 1,
    'late'    => 2,
    'excused' => 3
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :school_id,       presence: true
  validates :grade_id,        presence: true
  validates :school_class_id, presence: true
  validates :learner_id,      presence: true
  validates :date,            presence: true
  validates :status,          presence: true, inclusion: { in: STATUSES.values }
  validates :recorded_by_id,  presence: true

  # ======================== INDEXES =======================
  index({ school_class_id: 1, learner_id: 1, date: 1 }, { unique: true })
  index({ school_id: 1, date: 1 })
  index({ learner_id: 1, date: 1 })
  index({ school_class_id: 1, date: 1 })

  # ========================= SCOPES ========================
  scope :by_school,     ->(school_id) { where(school_id: school_id.to_s) }
  scope :by_class,      ->(school_class_id) { where(school_class_id: school_class_id.to_s) }
  scope :by_learner,    ->(learner_id) { where(learner_id: learner_id.to_s) }
  scope :by_date_range, ->(from_date, to_date) {
    query = {}
    query[:$gte] = from_date.to_date if from_date.present?
    query[:$lte] = to_date.to_date   if to_date.present?
    query.present? ? where(date: query) : all
  }
  scope :present,       -> { where(status: 0) }
  scope :absent,        -> { where(status: 1) }
  scope :late,          -> { where(status: 2) }
  scope :excused,       -> { where(status: 3) }

  # ========================= METHODS ========================
  def status_text
    STATUSES.key(status) || 'unknown'
  end

  def learner_name
    return nil if learner_id.blank?

    lid_str = learner_id.to_s
    lid_bson = BSON::ObjectId.legal?(lid_str) ? BSON::ObjectId.from_string(lid_str) : nil

    doc = Learner.collection.find(
      "_id" => { "$in" => [lid_str, lid_bson].compact }
    ).first

    return nil unless doc

    learner = Learner.instantiate(doc)
    learner.try(:full_name) || "#{doc['first_name'] || doc['firstName']} #{doc['last_name'] || doc['lastName']}".strip
  rescue => e
    Rails.logger.error "❌ Error resolving learner_name for AttendanceRecord #{id}: #{e.message}"
    nil
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      grade_id: grade_id.to_s,
      school_class_id: school_class_id.to_s,
      learner_id: learner_id.to_s,
      learner_name: learner_name,
      date: date&.iso8601,
      status: status,
      status_text: status_text,
      note: note,
      recorded_by_id: recorded_by_id.to_s,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
