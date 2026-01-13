# app/models/learner_invitation.rb
class LearnerInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  # Core fields
  field :token, type: String
  field :status, type: String, default: 'pending'   # pending, accepted, declined, expired, cancelled
  field :role, type: String, default: 'parent'      # parent, teacher

  # Sender information
  field :sender_id, type: BSON::ObjectId

  # Recipient information
  field :recipient_phone_number, type: String
  field :phone_number, type: String
  field :parent_name, type: String
  field :country_code, type: String
  field :country_name, type: String

  # School and learner info
  field :school_id, type: String
  field :grade_id, type: String
  field :learner_number, type: String
  field :learner_numbers, type: Array, default: []
  field :learner_ids, type: Array, default: []

  # Invitation metadata
  field :invited_via, type: String, default: 'whatsapp'
  field :invited_at, type: Time
  field :accepted_at, type: Time
  field :expired_at, type: Time
  field :cancelled_at, type: Time

  # ======================== INDEXES ========================
  index({ token: 1 }, { unique: true })
  index({ status: 1 })
  index({ school_id: 1 })
  index({ recipient_phone_number: 1 })
  index({ grade_id: 1 })

  # ======================== VALIDATIONS ========================
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending accepted declined expired cancelled] }
  validates :recipient_phone_number, presence: true
  validates :school_id, presence: true

  validate :learner_info_present

  # ======================== ASSOCIATIONS ========================
  belongs_to :sender, class_name: 'User', optional: true, foreign_key: :sender_id
  belongs_to :grade, class_name: 'Grade', optional: true

  # ======================== SCOPES ========================
  scope :pending, -> { where(status: 'pending') }
  scope :accepted, -> { where(status: 'accepted') }
  scope :declined, -> { where(status: 'declined') }
  scope :expired, -> { where(status: 'expired') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :for_school, ->(school_id) { where(school_id: school_id.to_s) }

  # ======================== CALLBACKS ========================
  before_validation :generate_token, if: -> { token.blank? }
  before_validation :set_invited_at, if: -> { invited_at.blank? }
  before_save :auto_expire

  # ======================== STATUS HELPERS ========================
  def pending?; status == 'pending'; end
  def accepted?; status == 'accepted'; end
  def declined?; status == 'declined'; end
  def expired?; status == 'expired' || (expires_at && expires_at < Time.current); end
  def cancelled?; status == 'cancelled'; end

  # ======================== ACTION METHODS ========================
  def accept!
    return false unless pending?
    update!(status: 'accepted', accepted_at: Time.current)
  end

  def decline!
    return false unless pending?
    update!(status: 'declined')
  end

  def cancel!
    return false unless pending?
    update!(status: 'cancelled', cancelled_at: Time.current)
  end

  def expire!
    return false unless pending?
    update!(status: 'expired', expired_at: Time.current)
  end

  # ======================== UTILITY METHODS ========================
  def to_api_hash
    {
      id: id.to_s,
      token: token,
      status: status,
      role: role,
      recipient_phone_number: recipient_phone_number,
      phone_number: phone_number,
      parent_name: parent_name,
      school_id: school_id,
      grade_id: grade_id,
      learner_number: learner_number,
      learner_numbers: learner_numbers,
      learner_ids: learner_ids,
      invited_via: invited_via,
      country_code: country_code,
      country_name: country_name,
      invited_at: invited_at,
      accepted_at: accepted_at,
      expired_at: expired_at,
      cancelled_at: cancelled_at,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def set_invited_at
    self.invited_at ||= Time.current
  end

  def auto_expire
    if pending? && expired_at && expired_at < Time.current
      self.status = 'expired'
    end
  end

  def learner_info_present
    if learner_number.blank? && learner_numbers.blank? && learner_ids.blank?
      errors.add(:base, "At least one learner_number, learner_numbers, or learner_ids must be present")
    end
  end
end
