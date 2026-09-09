# app/models/term.rb
class Term
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :school_id,     type: String
  field :academic_year, type: Integer, default: -> { Date.current.year }
  field :term_number,   type: Integer
  field :name,          type: String
  field :start_date,    type: Date
  field :end_date,      type: Date

  # ===================== VALIDATIONS ======================
  validates :school_id,     presence: true
  validates :academic_year, presence: true, numericality: { only_integer: true }
  validates :term_number,   presence: true, inclusion: { in: 1..4 }
  validates :term_number,   uniqueness: { scope: [:school_id, :academic_year], message: "already exists for this school and academic year" }
  validates :start_date,    presence: true
  validates :end_date,      presence: true

  validate :validate_end_after_start
  validate :validate_no_date_overlap

  # ======================== INDEXES =======================
  index({ school_id: 1, academic_year: 1, term_number: 1 }, { unique: true })
  index({ school_id: 1, start_date: 1, end_date: 1 })

  # ======================== CALLBACKS =======================
  before_validation :set_default_name, if: -> { name.blank? && term_number.present? }

  # ========================= SCOPES ========================
  scope :by_school,        ->(school_id) { where(school_id: school_id.to_s) }
  scope :by_academic_year, ->(year) { where(academic_year: year.to_i) }

  # ========================= CLASS METHODS ========================
  def self.current_for_school(school_id)
    return nil if school_id.blank?

    today = Date.current
    where(
      school_id: school_id.to_s,
      :start_date.lte => today,
      :end_date.gte => today
    ).first
  rescue => e
    Rails.logger.error "❌ Error in Term.current_for_school(#{school_id}): #{e.message}"
    nil
  end

  # ========================= INSTANCE METHODS ========================
  def is_current?
    return false if start_date.blank? || end_date.blank?
    today = Date.current
    start_date <= today && today <= end_date
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      academic_year: academic_year,
      term_number: term_number,
      name: name,
      start_date: start_date&.iso8601,
      end_date: end_date&.iso8601,
      is_current: is_current?,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  private

  def set_default_name
    self.name = "Term #{term_number}"
  end

  def validate_end_after_start
    return if start_date.blank? || end_date.blank?

    if end_date <= start_date
      errors.add(:end_date, "must be after start_date")
    end
  end

  def validate_no_date_overlap
    return if school_id.blank? || academic_year.blank? || start_date.blank? || end_date.blank?

    # Check for overlapping date ranges within the same school and academic year
    overlapping = Term.where(
      school_id: school_id.to_s,
      academic_year: academic_year.to_i,
      :start_date.lte => end_date,
      :end_date.gte => start_date
    )

    overlapping = overlapping.where(:_id.ne => id) if persisted?

    if overlapping.exists?
      conflict = overlapping.first
      errors.add(:base, "Date range (#{start_date} to #{end_date}) overlaps with existing #{conflict.name} (#{conflict.start_date} to #{conflict.end_date})")
    end
  end
end
