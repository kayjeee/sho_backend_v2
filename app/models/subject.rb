# app/models/subject.rb
class Subject
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,        type: String
  field :code,        type: String
  field :description, type: String
  field :school_id,   type: String
  field :grade_ids,   type: Array, default: []
  field :status,      type: Integer, default: 0

  # ===================== CONSTANTS =======================
  STATUSES = {
    'active'   => 0,
    'inactive' => 1
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :name, presence: true, uniqueness: { scope: :school_id, case_sensitive: false }
  validates :school_id, presence: true
  validates :status, inclusion: { in: STATUSES.values }

  # ======================== INDEXES =======================
  index({ school_id: 1, name: 1 }, { unique: true })
  index({ school_id: 1, status: 1 })

  # ========================= SCOPES ========================
  scope :by_school, ->(school_id) { where(school_id: school_id.to_s) }
  scope :active,    -> { where(status: 0) }
  scope :inactive,  -> { where(status: 1) }

  # ========================= METHODS ========================
  def active?
    status == 0
  end

  def inactive?
    status == 1
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  def activate!
    update!(status: 0)
    Rails.logger.info "✅ Subject activated: #{name} (#{id})"
    true
  end

  def deactivate!
    update!(status: 1)
    Rails.logger.info "⏸️ Subject deactivated: #{name} (#{id})"
    true
  end

  def grade_names
    return [] if grade_ids.blank?

    gid_strings = Array(grade_ids).map(&:to_s).reject(&:blank?)
    return [] if gid_strings.empty?

    gid_bsons = gid_strings.map { |s| BSON::ObjectId.legal?(s) ? BSON::ObjectId.from_string(s) : nil }.compact
    all_ids = (gid_strings + gid_bsons).uniq

    found_grades = Grade.where(:id.in => all_ids).to_a
    grade_map = found_grades.each_with_object({}) do |g, hash|
      hash[g.id.to_s] = g.name
    end

    gid_strings.map { |gid| grade_map[gid] }.compact
  rescue => e
    Rails.logger.error "❌ Error resolving grade_names for subject #{id}: #{e.message}"
    []
  end

  def to_api_hash
    {
      id: id.to_s,
      name: name,
      code: code,
      description: description,
      status: status,
      status_text: status_text,
      school_id: school_id.to_s,
      grade_ids: Array(grade_ids).map(&:to_s),
      grade_names: grade_names,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
