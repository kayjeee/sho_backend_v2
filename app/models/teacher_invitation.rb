# app/models/teacher_invitation.rb
class TeacherInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  # Core fields
  field :token_hash, type: String
  field :status, type: String, default: 'pending'   # pending, accepted, declined, expired, cancelled
  field :role, type: String, default: 'teacher'

  # Sender information
  field :sender_id, type: BSON::ObjectId

  # Recipient information
  field :recipient_phone_number, type: String
  field :phone_number, type: String
  field :teacher_name, type: String
  field :country_code, type: String
  field :country_name, type: String

  # School and grade information
  field :school_id, type: String
  field :grade_id, type: String
  field :grade_ids, type: Array, default: []

  # Invitation metadata
  field :invited_via, type: String, default: 'whatsapp'
  field :invited_at, type: Time
  field :accepted_at, type: Time
  field :expired_at, type: Time
  field :cancelled_at, type: Time

  # Virtual attribute for the raw token (not persisted)
  attr_reader :token

  # ======================== INDEXES =======================
  index({ token_hash: 1 }, { unique: true })
  index({ status: 1 })
  index({ school_id: 1 })
  index({ recipient_phone_number: 1 })

  # ===================== VALIDATIONS ======================
  validates :token_hash, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending accepted declined expired cancelled] }
  validates :recipient_phone_number, presence: true
  validates :school_id, presence: true

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User', optional: true, foreign_key: :sender_id

  # ========================= SCOPES =======================
  scope :pending, -> { where(status: 'pending') }
  scope :accepted, -> { where(status: 'accepted') }
  scope :expired, -> { where(status: 'expired') }
  scope :for_school, ->(school_id) { where(school_id: school_id.to_s) }

  # ========================= CALLBACKS ====================
  before_validation :generate_and_hash_token, if: -> { token_hash.blank? }
  before_validation :set_defaults

  # ========================= METHODS ======================
  # Status helpers
  def pending?; status == 'pending'; end
  def accepted?; status == 'accepted'; end
  def declined?; status == 'declined'; end
  def expired?; status == 'expired' || (expired_at.present? && expired_at < Time.current); end
  def cancelled?; status == 'cancelled'; end

  # Invitation actions
  def accept!
    update!(status: 'accepted', accepted_at: Time.current)
  end

  def decline!
    update!(status: 'declined')
  end

  def cancel!
    update!(status: 'cancelled', cancelled_at: Time.current)
  end

  def expire!
    update!(status: 'expired', expired_at: Time.current)
  end

  def school_name
    school = School.where(id: school_id).first
    school&.schoolName || school&.name || 'Unknown School'
  end

  def school_slug
    school = School.where(id: school_id).first
    school&.try(:slug) || school&.schoolName&.parameterize || school&.name&.parameterize || 'unknown-school'
  end

  # API serialization
  def to_api_hash
    # We only return the raw token during creation.
    # For existing records, the token is not stored and cannot be retrieved.
    s_name = school_name
    s_slug = school_slug

    {
      id: id.to_s,
      token: @token,
      status: status,
      role: role,
      recipient_phone_number: recipient_phone_number,
      phone_number: phone_number,
      teacher_name: teacher_name,
      school_id: school_id,
      school_name: s_name,
      school_slug: s_slug,
      grade_id: grade_id,
      grade_ids: grade_ids,
      invited_via: invited_via,
      country_code: country_code,
      country_name: country_name,
      invited_at: invited_at,
      accepted_at: accepted_at,
      expired_at: expired_at,
      cancelled_at: cancelled_at,
      created_at: created_at,
      updated_at: updated_at,
      magic_link_query: "/#{URI.encode_www_form_component(s_name)}?token=#{@token}&school=#{URI.encode_www_form_component(s_name)}",
      full_magic_link: "#{ENV['TEACHER_APP_URL'] || 'http://localhost:3000'}/schools/#{s_slug}/teacher/invite/#{@token}"
    }
  end

  # Find an invitation by its raw token
  def self.find_by_token(token)
    return nil if token.blank?
    hash = Digest::SHA256.hexdigest(token)
    where(token_hash: hash).first
  end

  private

  def generate_and_hash_token
    @token = SecureRandom.urlsafe_base64(32)
    self.token_hash = Digest::SHA256.hexdigest(@token)
  end

  def set_defaults
    self.invited_at ||= Time.current
    self.expired_at ||= 7.days.from_now
    self.status     ||= 'pending'
  end
end
