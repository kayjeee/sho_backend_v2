# app/models/learner_invitation.rb
class LearnerInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== CONSTANTS ========================
  VALID_STATUSES = %w[pending accepted declined expired cancelled].freeze
  VALID_ROLES    = %w[parent teacher].freeze
  DEFAULT_EXPIRATION_DAYS = 7
  TOKEN_LENGTH   = 32

  # ======================== FIELDS ========================
  field :token,                  type: String
  field :status,                 type: String, default: 'pending'
  field :role,                   type: String, default: 'parent'

  # Sender & Recipient Information
  field :sender_id,              type: BSON::ObjectId
  field :recipient_phone_number, type: String
  field :phone_number,           type: String
  field :parent_name,            type: String
  field :country_code,           type: String
  field :country_name,           type: String

  # School & Learner Identifiers
  field :school_id,              type: String
  field :grade_id,               type: String
  field :learner_number,         type: String
  field :learner_numbers,        type: Array, default: []
  field :learner_ids,            type: Array, default: []

  # Metadata
  field :invited_via,            type: String, default: 'whatsapp'
  field :invited_at,             type: Time
  field :accepted_at,            type: Time
  field :expired_at,             type: Time
  field :cancelled_at,           type: Time

  # ======================== INDEXES ========================
  index({ token: 1 }, { unique: true })
  index({ school_id: 1 })
  index({ status: 1 })
  index({ recipient_phone_number: 1 })

  # ======================== VALIDATIONS ========================
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: VALID_STATUSES }
  validates :role, inclusion: { in: VALID_ROLES }
  validates :recipient_phone_number, :school_id, presence: true

  validate :learner_info_present
  validate :expiration_date_in_future, on: :create

  # ======================== ASSOCIATIONS ========================
  belongs_to :sender, class_name: 'User', optional: true, foreign_key: :sender_id
  belongs_to :grade,  optional: true

  # ======================== CALLBACKS ========================
  before_validation :generate_token, if: -> { token.blank? }
  before_validation :set_defaults
  before_validation :normalize_phone_numbers
  before_save :auto_expire

  # ======================== DYNAMIC FETCHERS ========================

  def school_logo
    return nil unless school_id.present?

    school = School.find(school_id) rescue School.where(id: BSON::ObjectId.from_string(school_id.to_s)).first rescue nil
    school&.logo
  rescue => e
    Rails.logger.error "❌ Error fetching school logo for invitation #{id}: #{e.message}"
    nil
  end

  def school_name
    school = School.where(id: school_id).first
    return 'Unknown School' unless school

    school.try(:schoolName) || school.try(:name) || school.try(:school_name) || 'Unknown School'
  end

  def sender_name
    user = User.where(id: sender_id).first
    user&.name || 'System'
  end

  def grade_name
    g = Grade.where(id: grade_id).first
    g&.name || g&.title || 'Unknown Grade'
  end

  # ======================== STATUS HELPERS ========================

  def pending?
    status == 'pending'
  end

  def expired?
    status == 'expired' || (expired_at.present? && expired_at <= Time.current)
  end

  def active?
    pending? && !expired?
  end

  def learner_count
    return learner_ids.size if learner_ids.present?
    return learner_numbers.size if learner_numbers.present?
    learner_number.present? ? 1 : 0
  end

  # ======================== MAGIC LINK ========================

  # Builds: /Far+North+Secondary+School?token=xxx&school=Far+North+Secondary+School
  def magic_link_query
    return "?token=#{token}" unless token.present?

    school_slug = school_name.to_s.strip.gsub(/\s+/, '+')
    encoded_school = URI.encode_www_form_component(school_name.to_s)
    "/#{school_slug}?token=#{token}&school=#{encoded_school}"
  rescue => e
    Rails.logger.warn "⚠️ Error generating magic link query: #{e.message}"
    "?token=#{token}"
  end

  # Builds: https://www.schoolheadoffice.com/parent/Far+North+Secondary+School?token=xxx&school=Far+North+Secondary+School
  def full_magic_link
    base = ENV['PARENT_APP_URL'] || 'https://www.schoolheadoffice.com/parent'
    school_slug = school_name.to_s.strip.gsub(/\s+/, '+')
    encoded_school = URI.encode_www_form_component(school_name.to_s)
    "#{base}/#{school_slug}?token=#{token}&school=#{encoded_school}"
  rescue => e
    Rails.logger.warn "⚠️ Error generating full magic link: #{e.message}"
    "#{ENV['PARENT_APP_URL'] || 'https://www.schoolheadoffice.com/parent'}?token=#{token}"
  end

  # ======================== API SERIALIZATION ========================

  def to_api_hash
    {
      id: id.to_s,
      token: token,
      status: status,
      role: role,

      # Recipient
      recipient_phone_number: recipient_phone_number,
      parent_name: parent_name,

      # School / Learner Data
      school_id: school_id,
      school_name: school_name,
      school_logo: school_logo,
      grade_id: grade_id,
      grade_name: grade_name,
      learner_number: learner_number,
      learner_numbers: learner_numbers || [],
      learner_ids: (learner_ids || []).map(&:to_s),
      learner_count: learner_count,
      multiple_learners: learner_count > 1,

      # Meta & Timestamps
      invited_via: invited_via,
      sender_id: sender_id&.to_s,
      sender_name: sender_name,
      invited_at: invited_at&.iso8601,
      accepted_at: accepted_at&.iso8601,
      expired_at: expired_at&.iso8601,
      cancelled_at: cancelled_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601,

      # Logic Checks
      active: active?,
      expired: expired?,
      expires_in_days: expires_in_days,
      expires_in_seconds: expires_in_seconds,

      # Link Generation
      magic_link_query: magic_link_query,
      full_magic_link: full_magic_link
    }
  rescue => e
    Rails.logger.error "❌ API Serialization failed for LearnerInvitation #{id}: #{e.message}"
    { id: id.to_s, token: token, status: 'error' }
  end

  def expires_in_days
    return nil unless expired_at
    days = ((expired_at - Time.current) / 1.day).ceil
    [days, 0].max
  end

  def expires_in_seconds
    return 0 unless expired_at
    seconds = (expired_at - Time.current).to_i
    [seconds, 0].max
  end

  private

  # ======================== LOGIC HELPERS ========================

  def generate_token
    self.token = SecureRandom.urlsafe_base64(TOKEN_LENGTH)
  end

  def set_defaults
    self.invited_at ||= Time.current
    self.expired_at ||= DEFAULT_EXPIRATION_DAYS.days.from_now
    self.status     ||= 'pending'
    self.role       ||= 'parent'
    self.invited_via ||= 'whatsapp'
    self.learner_numbers ||= []
    self.learner_ids     ||= []
  end

  def normalize_phone_numbers
    self.recipient_phone_number = recipient_phone_number.to_s.gsub(/\s+/, '') if recipient_phone_number.present?
    self.phone_number = phone_number.to_s.gsub(/\s+/, '') if phone_number.present?
  end

  def auto_expire
    if status == 'pending' && expired_at.present? && expired_at <= Time.current
      self.status = 'expired'
    end
  end

  def learner_info_present
    if learner_number.blank? && learner_numbers.blank? && learner_ids.blank?
      errors.add(:base, 'At least one learner identifier (number or ID) must be provided')
    end
  end

  def expiration_date_in_future
    if expired_at.present? && expired_at <= Time.current
      errors.add(:expired_at, 'must be in the future')
    end
  end
end