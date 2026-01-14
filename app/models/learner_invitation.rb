# app/models/learner_invitation.rb
class LearnerInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== CONSTANTS ========================
  VALID_STATUSES = %w[pending accepted declined expired cancelled].freeze
  VALID_ROLES = %w[parent teacher].freeze
  DEFAULT_EXPIRATION_DAYS = 7
  TOKEN_LENGTH = 32

  # ======================== FIELDS ========================
  # Core fields
  field :token, type: String
  field :status, type: String, default: 'pending'
  field :role, type: String, default: 'parent'

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
  index({ expired_at: 1 })
  index({ sender_id: 1 })

  # ======================== VALIDATIONS ========================
  validates :token, presence: true, uniqueness: true
  validates :status, inclusion: { in: VALID_STATUSES }
  validates :role, inclusion: { in: VALID_ROLES }
  validates :recipient_phone_number, presence: true
  validates :school_id, presence: true

  validate :learner_info_present
  validate :expiration_date_in_future, on: :create

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
  scope :for_recipient, ->(phone) { where(recipient_phone_number: phone) }
  scope :active, -> { pending.where(:expired_at.gt => Time.current) }
  scope :expired_auto, -> { pending.where(:expired_at.lte => Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  # ======================== CALLBACKS ========================
  before_validation :generate_token, if: -> { token.blank? }
  before_validation :set_invited_at, if: -> { invited_at.blank? }
  before_validation :set_default_expiration, if: -> { expired_at.blank? }
  before_validation :normalize_phone_numbers
  before_save :auto_expire
  after_initialize :set_defaults

  # ======================== CLASS METHODS ========================
  class << self
    def find_by_token(token)
      where(token: token).first
    end

    def generate_unique_token
      loop do
        token = SecureRandom.urlsafe_base64(TOKEN_LENGTH)
        break token unless where(token: token).exists?
      end
    end

    def expire_old_invitations
      expired_count = 0
      expired_auto.each do |invitation|
        if invitation.expire!
          expired_count += 1
        end
      end
      Rails.logger.info "✅ Expired #{expired_count} old invitations"
      expired_count
    end
  end

  # ======================== STATUS HELPERS ========================
  def pending?
    status == 'pending'
  end

  def accepted?
    status == 'accepted'
  end

  def declined?
    status == 'declined'
  end

  def expired?
    status == 'expired' || (expired_at.present? && expired_at <= Time.current)
  end

  def cancelled?
    status == 'cancelled'
  end

  def active?
    pending? && !expired?
  end

  # ======================== ACTION METHODS ========================
  def accept!
    return false unless can_accept?
    
    update!(
      status: 'accepted',
      accepted_at: Time.current
    )
  rescue => e
    Rails.logger.error "❌ Failed to accept invitation #{id}: #{e.message}"
    false
  end

  def decline!
    return false unless can_decline?
    
    update!(status: 'declined')
  rescue => e
    Rails.logger.error "❌ Failed to decline invitation #{id}: #{e.message}"
    false
  end

  def cancel!
    return false unless can_cancel?
    
    update!(
      status: 'cancelled',
      cancelled_at: Time.current
    )
  rescue => e
    Rails.logger.error "❌ Failed to cancel invitation #{id}: #{e.message}"
    false
  end

  def expire!
    return false unless can_expire?
    
    update!(
      status: 'expired',
      expired_at: Time.current
    )
  rescue => e
    Rails.logger.error "❌ Failed to expire invitation #{id}: #{e.message}"
    false
  end

  # ======================== PERMISSION CHECKS ========================
  def can_accept?
    pending? && !expired?
  end

  def can_decline?
    pending? && !expired?
  end

  def can_cancel?
    pending?
  end

  def can_expire?
    pending?
  end

  # ======================== COMPUTED ATTRIBUTES ========================
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

  def school_name
    @school_name ||= fetch_school_name
  end

  def sender_name
    @sender_name ||= fetch_sender_name
  end

  def grade_name
    @grade_name ||= fetch_grade_name
  end

  def learner_count
    return learner_ids.size if learner_ids.present?
    return learner_numbers.size if learner_numbers.present?
    learner_number.present? ? 1 : 0
  end

  def multiple_learners?
    learner_count > 1
  end

  # ======================== MAGIC LINK METHODS ========================
  def magic_link_query
    return nil unless token.present?
    
    encoded_school = URI.encode_www_form_component(school_name)
    "?token=#{token}&school=#{encoded_school}"
  rescue => e
    Rails.logger.warn "⚠️ Error generating magic link query: #{e.message}"
    "?token=#{token}"
  end

  def full_magic_link
    base_url = ENV['PARENT_APP_URL'] || 'https://www.schoolheadoffice.com/parent'
    "#{base_url}#{magic_link_query}"
  end

  # ======================== API SERIALIZATION ========================
  def to_api_hash
    {
      id: id.to_s,
      token: token,
      status: status,
      role: role,
      
      # Recipient info
      recipient_phone_number: recipient_phone_number,
      phone_number: phone_number,
      parent_name: parent_name,
      country_code: country_code,
      country_name: country_name,
      
      # School and learner info
      school_id: school_id,
      school_name: school_name,
      grade_id: grade_id,
      grade_name: grade_name,
      learner_number: learner_number,
      learner_numbers: learner_numbers || [],
      learner_ids: (learner_ids || []).map(&:to_s),
      learner_count: learner_count,
      multiple_learners: multiple_learners?,
      
      # Metadata
      invited_via: invited_via,
      sender_id: sender_id&.to_s,
      sender_name: sender_name,
      
      # Timestamps
      invited_at: invited_at&.iso8601,
      accepted_at: accepted_at&.iso8601,
      expired_at: expired_at&.iso8601,
      cancelled_at: cancelled_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601,
      
      # Status flags
      expired: expired?,
      active: active?,
      expires_in_days: expires_in_days,
      expires_in_seconds: expires_in_seconds,
      
      # Magic links
      magic_link_query: magic_link_query,
      full_magic_link: full_magic_link
    }
  rescue => e
    Rails.logger.error "❌ Error generating API hash for invitation #{id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Return minimal safe hash
    {
      id: id.to_s,
      token: token,
      status: status,
      error: 'Could not generate full invitation details'
    }
  end

  def to_json(options = {})
    to_api_hash.to_json(options)
  end

  private

  # ======================== CALLBACKS ========================
  def generate_token
    self.token = self.class.generate_unique_token
  end

  def set_invited_at
    self.invited_at = Time.current
  end

  def set_default_expiration
    self.expired_at = DEFAULT_EXPIRATION_DAYS.days.from_now
  end

  def set_defaults
    self.status ||= 'pending'
    self.role ||= 'parent'
    self.invited_via ||= 'whatsapp'
    self.learner_numbers ||= []
    self.learner_ids ||= []
    
    if new_record? && expired_at.blank?
      self.expired_at = DEFAULT_EXPIRATION_DAYS.days.from_now
    end
  end

  def normalize_phone_numbers
    self.recipient_phone_number = normalize_phone(recipient_phone_number) if recipient_phone_number.present?
    self.phone_number = normalize_phone(phone_number) if phone_number.present?
  end

  def normalize_phone(phone)
    phone.to_s.strip.gsub(/\s+/, '')
  end

  def auto_expire
    if pending? && expired_at.present? && expired_at <= Time.current
      self.status = 'expired'
    end
  end

  # ======================== VALIDATIONS ========================
  def learner_info_present
    if learner_number.blank? && learner_numbers.blank? && learner_ids.blank?
      errors.add(:base, 'At least one learner identifier must be present')
    end
  end

  def expiration_date_in_future
    if expired_at.present? && expired_at <= Time.current
      errors.add(:expired_at, 'must be in the future')
    end
  end

  # ======================== FETCHERS ========================
  def fetch_school_name
    return 'Unknown School' unless school_id.present?
    
    school = School.where(id: school_id).first
    return 'Unknown School' unless school
    
    # ✅ FIXED: Check schoolName first (since that's the actual field name in your School model)
    # School model has schoolName field, not name field
    if school.respond_to?(:schoolName) && school.schoolName.present?
      school.schoolName
    elsif school.respond_to?(:name) && school.name.present?
      school.name
    elsif school.respond_to?(:school_name) && school.school_name.present?
      school.school_name
    elsif school.respond_to?(:title) && school.title.present?
      school.title
    else
      'Unknown School'
    end
  rescue => e
    Rails.logger.error "❌ Error fetching school name for invitation #{id}: #{e.message}"
    'Unknown School'
  end

  def fetch_sender_name
    return 'System' unless sender_id.present?
    
    sender_user = User.where(id: sender_id).first
    return 'System' unless sender_user
    
    sender_user.full_name ||
      sender_user.name ||
      sender_user.email&.split('@')&.first ||
      'Unknown Sender'
  rescue => e
    Rails.logger.error "❌ Error fetching sender name for invitation #{id}: #{e.message}"
    'System'
  end

  def fetch_grade_name
    return nil unless grade_id.present?
    
    grade_obj = Grade.where(id: grade_id).first
    return nil unless grade_obj
    
    grade_obj.name || grade_obj.grade_name || grade_obj.title
  rescue => e
    Rails.logger.error "❌ Error fetching grade name for invitation #{id}: #{e.message}"
    nil
  end
end