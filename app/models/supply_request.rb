# app/models/supply_request.rb
class SupplyRequest
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :school_id,      type: String
  field :teacher_id,     type: String
  field :item_type,      type: String, default: 'paper'
  field :quantity,       type: Integer
  field :unit,           type: String, default: 'pages'
  field :reason,         type: String
  field :status,         type: Integer, default: 0
  field :requested_at,   type: DateTime, default: -> { Time.current }
  field :reviewed_by_id, type: String
  field :reviewed_at,    type: DateTime
  field :fulfilled_at,   type: DateTime
  field :admin_note,     type: String

  # ===================== CONSTANTS =======================
  STATUSES = {
    'pending'   => 0,
    'approved'  => 1,
    'rejected'  => 2,
    'fulfilled' => 3
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :school_id,   presence: true
  validates :teacher_id,  presence: true
  validates :quantity,    presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status,      presence: true, inclusion: { in: STATUSES.values }

  validate :validate_teacher_belongs_to_school

  # ======================== INDEXES =======================
  index({ school_id: 1, status: 1 })
  index({ teacher_id: 1, status: 1 })
  index({ requested_at: -1 })

  # ========================= SCOPES ========================
  scope :by_school,  ->(school_id) { where(school_id: school_id.to_s) }
  scope :by_teacher, ->(teacher_id) { where(teacher_id: teacher_id.to_s) }
  scope :pending,   -> { where(status: 0) }
  scope :approved,  -> { where(status: 1) }
  scope :rejected,  -> { where(status: 2) }
  scope :fulfilled, -> { where(status: 3) }

  # ========================= METHODS ========================
  def status_text
    STATUSES.key(status) || 'unknown'
  end

  def approve!(reviewer_id, note = nil)
    unless status == 0 # Only pending can be approved
      errors.add(:status, "cannot transition from #{status_text} to approved")
      return false
    end

    update(
      status: 1,
      reviewed_by_id: reviewer_id.to_s,
      reviewed_at: Time.current,
      admin_note: note.presence || admin_note
    )
  end

  def reject!(reviewer_id, note = nil)
    unless status == 0 # Only pending can be rejected
      errors.add(:status, "cannot transition from #{status_text} to rejected")
      return false
    end

    update(
      status: 2,
      reviewed_by_id: reviewer_id.to_s,
      reviewed_at: Time.current,
      admin_note: note.presence || admin_note
    )
  end

  def fulfill!(reviewer_id = nil, note = nil)
    unless status == 1 # Only approved can be fulfilled
      errors.add(:status, "cannot transition from #{status_text} to fulfilled")
      return false
    end

    updates = {
      status: 3,
      fulfilled_at: Time.current
    }
    updates[:reviewed_by_id] = reviewer_id.to_s if reviewer_id.present?
    updates[:admin_note] = note if note.present?

    update(updates)
  end

  def teacher_name
    resolve_user_name(teacher_id)
  end

  def reviewed_by_name
    resolve_user_name(reviewed_by_id)
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      teacher_id: teacher_id.to_s,
      teacher_name: teacher_name,
      item_type: item_type,
      quantity: quantity,
      unit: unit,
      reason: reason,
      status: status,
      status_text: status_text,
      requested_at: requested_at&.iso8601,
      reviewed_by_id: reviewed_by_id.presence,
      reviewed_by_name: reviewed_by_name,
      reviewed_at: reviewed_at&.iso8601,
      fulfilled_at: fulfilled_at&.iso8601,
      admin_note: admin_note,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  private

  def resolve_user_name(user_id)
    return nil if user_id.blank?

    u_str = user_id.to_s
    u_bson = BSON::ObjectId.legal?(u_str) ? BSON::ObjectId.from_string(u_str) : nil

    u_doc = User.collection.find(
      "$or" => [
        { "_id" => { "$in" => [u_str, u_bson].compact } },
        { "auth0_id" => u_str }
      ]
    ).first

    return nil unless u_doc

    user = User.instantiate(u_doc)
    user.try(:full_name) || user.try(:name) || "#{u_doc['name'] || u_doc['display_name']}".strip
  rescue => e
    Rails.logger.error "❌ Error resolving user_name for SupplyRequest #{id}: #{e.message}"
    nil
  end

  def validate_teacher_belongs_to_school
    return if teacher_id.blank? || school_id.blank?

    t_str = teacher_id.to_s
    t_bson = BSON::ObjectId.legal?(t_str) ? BSON::ObjectId.from_string(t_str) : nil
    s_str = school_id.to_s

    user_doc = User.collection.find(
      "$or" => [
        { "_id" => { "$in" => [t_str, t_bson].compact } },
        { "auth0_id" => t_str }
      ]
    ).first

    unless user_doc
      errors.add(:teacher_id, "Teacher user not found")
      return
    end

    user_school_ids = Array(user_doc["school_ids"]).map(&:to_s)
    user_school_ids << user_doc["school_id"].to_s if user_doc["school_id"].present?

    unless user_school_ids.include?(s_str)
      errors.add(:teacher_id, "does not belong to target school")
    end
  end
end
