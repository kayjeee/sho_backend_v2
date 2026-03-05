# app/models/invitation.rb
class Invitation
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User', optional: true
  belongs_to :school, optional: true

  # ===================== CORE INVITATION FIELDS =====================
  field :token,                  type: String
  field :status,                 type: String, default: 'pending'
  field :recipient_phone_number, type: String
  field :role,                   type: String, default: 'parent'
  field :invited_via,            type: String, default: 'whatsapp'
  field :parent_name,            type: String
  field :grade_id,               type: String
  field :sender_email,           type: String
  field :school_logo,            type: String

  # ===================== LEARNER INFORMATION =====================
  field :learner_number,  type: String
  field :learner_numbers, type: Array, default: []
  field :learner_ids,     type: Array, default: []
  field :learner_names,   type: Array, default: []

  # ===================== TIMESTAMP FIELDS =====================
  field :accepted_at,      type: Time
  field :expires_at,       type: Time
  field :magic_link_sent_at, type: Time

  # ===================== ADDITIONAL DATA =====================
  field :metadata,         type: Hash,   default: {}
  field :notes,            type: String
  field :invitation_type,  type: String, default: 'standard'

  # ===================== VALIDATIONS =====================
  validates :token, presence: true, uniqueness: true
  validates :recipient_phone_number, presence: true
  validates :role,       presence: true, inclusion: { in: %w[parent teacher admin student] }
  validates :status,     inclusion: { in: %w[pending accepted expired rejected cancelled] }
  validates :invited_via, inclusion: { in: %w[whatsapp sms email direct link] }
  validate  :validate_learner_data_consistency
  validate  :validate_phone_number_format

  # ===================== INDEXES =====================
  index({ token: 1 },                        { unique: true })
  index({ status: 1 })
  index({ role: 1 })
  index({ recipient_phone_number: 1 })
  index({ school_id: 1 })
  index({ sender_id: 1 })
  index({ created_at: -1 })
  index({ expires_at: 1 })
  index({ accepted_at: 1 })
  index({ magic_link_sent_at: 1 })
  index({ status: 1, expires_at: 1 })
  index({ school_id: 1, status: 1 })
  index({ recipient_phone_number: 1, status: 1 })
  index({ learner_ids: 1 })
  index({ learner_numbers: 1 })
  index({ learner_ids: 1, status: 1 })
  index({ token: 1, status: 1 })

  # ===================== CALLBACKS =====================
  before_validation :generate_token, unless: :token?
  before_create     :set_default_expiration
  before_save       :sync_legacy_learner_fields
  after_save        :update_status_if_expired

  # ===================== SCOPES =====================
  scope :pending,   -> { where(status: 'pending') }
  scope :accepted,  -> { where(status: 'accepted') }
  scope :expired,   -> { where(status: 'expired') }
  scope :rejected,  -> { where(status: 'rejected') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :active,    -> { pending.where(:expires_at.gt => Time.current) }
  scope :inactive,  -> { where(:status.in => ['accepted', 'rejected', 'cancelled', 'expired']) }

  scope :by_school,         ->(school_id) { where(school_id: school_id) }
  scope :by_sender,         ->(sender_id) { where(sender_id: sender_id) }
  scope :by_recipient_phone, ->(phone)   { where(recipient_phone_number: phone) }
  scope :by_learner_id,     ->(id)       { where(learner_ids: id) }
  scope :by_learner_number, ->(number)   { where(learner_numbers: number) }
  scope :with_token,        ->(token)    { where(token: token) }
  scope :recent,            ->           { order(created_at: :desc) }
  scope :expiring_soon,     ->(hours = 24) {
    pending.where(:expires_at.lte => hours.hours.from_now, :expires_at.gt => Time.current)
  }
  scope :expired_auto, -> { pending.where(:expires_at.lte => Time.current) }
  scope :not_sent,     -> { where(magic_link_sent_at: nil) }

  # ===================== CLASS METHODS =====================

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.find_by_token(token)
    where(token: token).first
  end

  def self.find_by(conditions = {})
    where(conditions).first
  end

  def self.create_for_learners(learners_data, invitation_params)
    invitations = []

    learners_data.each_slice(50) do |batch|
      batch.each do |learner_data|
        invitation = new(invitation_params.merge(
          learner_ids:     [learner_data[:id]],
          learner_numbers: [learner_data[:accession_number]],
          learner_names:   [learner_data[:name]],
          learner_number:  learner_data[:accession_number]
        ))
        invitations << invitation if invitation.save
      end
    end

    invitations
  end

  # Builds the query portion only (used in to_notification_hash)
  # Returns: /Far+North+Secondary+School?token=xxx&school=Far+North+Secondary+School
  def self.build_magic_link(token, school_name_str)
    return nil unless token.present? && school_name_str.present?

    school_slug   = school_name_str.to_s.strip.gsub(/\s+/, '+')
    encoded_school = URI.encode_www_form_component(school_name_str.to_s.strip)
    "/#{school_slug}?token=#{token}&school=#{encoded_school}"
  end

  # ===================== INSTANCE METHODS =====================

  def pending?
    status == 'pending'
  end

  def valid_invitation?
    status == 'pending' && !expired?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def accept!
    update(status: 'accepted', accepted_at: Time.current)
  end

  def expire!
    update(status: 'expired')
  end

  def reject!
    update(status: 'rejected')
  end

  def cancel!
    update(status: 'cancelled')
  end

  def extend_expiration!(days = 7)
    update(expires_at: (expires_at || Time.current) + days.days)
  end

  def resend!
    update(
      token:            self.class.generate_token,
      status:           'pending',
      expires_at:       7.days.from_now,
      accepted_at:      nil,
      magic_link_sent_at: nil
    )
  end

  def mark_as_sent!
    update(magic_link_sent_at: Time.current)
  end

  def magic_link_sent?
    magic_link_sent_at.present?
  end

  def sender_name
    sender&.full_name || sender&.name || 'System'
  end

  def school_name
    school&.schoolName || school&.name || 'Unknown School'
  end

  def multiple_learners?
    learner_ids.present? && learner_ids.size > 1
  end

  def learner_count
    learner_ids&.size || (learner_number.present? ? 1 : 0)
  end

  def learner_names_display
    return 'No learners' if learner_names.blank?

    case learner_names.size
    when 1 then learner_names.first
    when 2 then learner_names.join(' and ')
    else        "#{learner_names[0..-2].join(', ')}, and #{learner_names.last}"
    end
  end

  def primary_learner
    {
      id:     learner_ids&.first,
      number: learner_numbers&.first || learner_number,
      name:   learner_names&.first
    }
  end

  def add_learner(learner_id, learner_number, learner_name)
    self.learner_ids     ||= []
    self.learner_numbers ||= []
    self.learner_names   ||= []

    unless learner_ids.include?(learner_id)
      self.learner_ids     << learner_id
      self.learner_numbers << learner_number
      self.learner_names   << learner_name
      self.learner_number = learner_number if self.learner_number.blank?
    end

    save
  end

  def remove_learner(learner_id)
    return false unless learner_ids.include?(learner_id)

    index = learner_ids.index(learner_id)
    self.learner_ids.delete_at(index)
    self.learner_numbers.delete_at(index)
    self.learner_names.delete_at(index)
    self.learner_number = learner_numbers.first if learner_number == learner_id.to_s

    save
  end

  # ===================== MAGIC LINK =====================

  # Returns: /Far+North+Secondary+School?token=xxx&school=Far+North+Secondary+School
  def magic_link_query
    self.class.build_magic_link(token, school_name)
  end

  # Returns: https://www.schoolheadoffice.com/parent/Far+North+Secondary+School?token=xxx&school=Far+North+Secondary+School
  def full_magic_link
    base = ENV['PARENT_APP_URL'] || 'https://www.schoolheadoffice.com/parent'
    "#{base}#{magic_link_query}"
  end

  # ===================== SERIALIZATION =====================

  def to_api_hash(include_token: true)
    {
      id:                     id.to_s,
      token:                  token,
      recipient_phone_number: recipient_phone_number,
      role:                   role,
      status:                 status,
      invited_via:            invited_via,
      parent_name:            parent_name,
      school_id:              school_id&.to_s,
      school_name:            school_name,
      school_logo:            school&.logo,
      sender_id:              sender_id&.to_s,
      sender_name:            sender_name,
      sender_email:           sender_email,
      learner_number:         learner_number,
      learner_numbers:        learner_numbers,
      learner_ids:            learner_ids,
      learner_names:          learner_names,
      learner_count:          learner_count,
      multiple_learners:      multiple_learners?,
      grade_id:               grade_id,
      accepted_at:            accepted_at&.iso8601,
      expires_at:             expires_at&.iso8601,
      expired:                expired?,
      valid:                  valid_invitation?,
      invitation_type:        invitation_type,
      metadata:               metadata,
      magic_link_sent_at:     magic_link_sent_at&.iso8601,
      created_at:             created_at&.iso8601,
      updated_at:             updated_at&.iso8601,
      magic_link_query:       magic_link_query,
      full_magic_link:        full_magic_link
    }
  end

  def to_notification_hash
    {
      id:                     id.to_s,
      token:                  token,
      recipient_phone_number: recipient_phone_number,
      learner_names:          learner_names_display,
      school_name:            school_name,
      expires_at:             expires_at&.strftime('%b %d, %Y'),
      magic_link_query:       magic_link_query,
      full_magic_link:        full_magic_link
    }
  end

  private

  def generate_token
    self.token ||= self.class.generate_token
  end

  def set_default_expiration
    self.expires_at ||= 7.days.from_now
  end

  def update_status_if_expired
    if status == 'pending' && expired?
      self.status = 'expired'
      save(validate: false) rescue nil
    end
  end

  def sync_legacy_learner_fields
    self.learner_number = learner_numbers.first if learner_number.blank? && learner_numbers.present?

    if learner_number.present? && learner_ids.blank?
      self.learner_ids     = [learner_number]
      self.learner_numbers = [learner_number]
      self.learner_names   = [learner_number]
    end
  end

  def validate_learner_data_consistency
    return if learner_ids.blank? && learner_number.blank?

    if learner_ids.present?
      if learner_numbers.present? && learner_ids.length != learner_numbers.length
        errors.add(:learner_numbers, 'must have same count as learner_ids')
      end
      if learner_names.present? && learner_ids.length != learner_names.length
        errors.add(:learner_names, 'must have same count as learner_ids')
      end
    end
  end

  def validate_phone_number_format
    return if recipient_phone_number.blank?

    unless recipient_phone_number.match?(/\A27\d{9}\z/)
      errors.add(:recipient_phone_number, 'must be a valid South African number (27XXXXXXXXX)')
    end
  end
end