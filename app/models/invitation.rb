# app/models/invitation.rb
class Invitation
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User', optional: true
  belongs_to :school, optional: true

  # ===================== CORE INVITATION FIELDS =====================
  field :token, type: String
  field :status, type: String, default: 'pending'
  field :recipient_phone_number, type: String
  field :role, type: String, default: 'parent'
  field :invited_via, type: String, default: 'whatsapp'
  field :parent_name, type: String
  field :grade_id, type: String

  # ===================== LEARNER INFORMATION =====================
  # Legacy field for backward compatibility (single learner)
  field :learner_number, type: String
  
  # New fields for multiple learner support
  field :learner_numbers, type: Array, default: []       # Array of accession numbers
  field :learner_ids, type: Array, default: []           # Array of learner MongoDB IDs
  field :learner_names, type: Array, default: []         # Array of learner full names

  # ===================== TIMESTAMP FIELDS =====================
  field :accepted_at, type: Time
  field :expires_at, type: Time
  
  # ===================== ADDITIONAL DATA =====================
  field :metadata, type: Hash, default: {}
  field :notes, type: String
  field :invitation_type, type: String, default: 'standard'

  # ===================== VALIDATIONS =====================
  validates :token, presence: true, uniqueness: true
  validates :recipient_phone_number, presence: true
  validates :role, presence: true, inclusion: { in: %w[parent teacher admin student] }
  validates :status, inclusion: { in: %w[pending accepted expired rejected cancelled] }
  validates :invited_via, inclusion: { in: %w[whatsapp sms email direct link] }
  validate :validate_learner_data_consistency
  validate :validate_phone_number_format

  # ===================== INDEXES =====================
  index({ token: 1 }, { unique: true })
  index({ status: 1 })
  index({ role: 1 })
  index({ recipient_phone_number: 1 })
  index({ school_id: 1 })
  index({ sender_id: 1 })
  index({ created_at: -1 })
  index({ expires_at: 1 })
  index({ accepted_at: 1 })
  
  # Multi-field indexes for common queries
  index({ status: 1, expires_at: 1 })
  index({ school_id: 1, status: 1 })
  index({ recipient_phone_number: 1, status: 1 })
  
  # Indexes for learner arrays
  index({ learner_ids: 1 })
  index({ learner_numbers: 1 })
  index({ learner_ids: 1, status: 1 })

  # ===================== CALLBACKS =====================
  before_validation :generate_token, unless: :token?
  before_create :set_default_expiration
  before_save :sync_legacy_learner_fields
  after_save :update_status_if_expired

  # ===================== SCOPES =====================
  scope :pending, -> { where(status: 'pending') }
  scope :accepted, -> { where(status: 'accepted') }
  scope :expired, -> { where(status: 'expired') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :active, -> { where(status: 'pending').where(:expires_at.gt => Time.current) }
  scope :inactive, -> { where(:status.in => ['accepted', 'rejected', 'cancelled', 'expired']) }
  
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_sender, ->(sender_id) { where(sender_id: sender_id) }
  scope :by_recipient_phone, ->(phone) { where(recipient_phone_number: phone) }
  scope :by_learner_id, ->(learner_id) { where(learner_ids: learner_id) }
  scope :by_learner_number, ->(number) { where(learner_numbers: number) }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :expiring_soon, ->(hours = 24) { 
    pending.where(:expires_at.lte => hours.hours.from_now, :expires_at.gt => Time.current) 
  }
  scope :expired_auto, -> { pending.where(:expires_at.lte => Time.current) }

  # ===================== CLASS METHODS =====================
  
  # Generate a unique invitation token
  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  # Find by token with case-insensitive match
  def self.find_by_token(token)
    where(token: /^#{Regexp.escape(token)}$/i).first
  end

  # Create multiple invitations for bulk operations
  def self.create_for_learners(learners_data, invitation_params)
    invitations = []
    
    learners_data.each_slice(50) do |batch|
      batch.each do |learner_data|
        invitation = new(invitation_params.merge(
          learner_ids: [learner_data[:id]],
          learner_numbers: [learner_data[:accession_number]],
          learner_names: [learner_data[:name]],
          learner_number: learner_data[:accession_number] # Legacy compatibility
        ))
        
        invitations << invitation if invitation.save
      end
    end
    
    invitations
  end

  # ===================== INSTANCE METHODS =====================

  # Check if invitation is still valid for acceptance
  def valid_invitation?
    status == 'pending' && !expired?
  end

  # Check if invitation has expired
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Mark invitation as accepted
  def accept!
    update(status: 'accepted', accepted_at: Time.current)
  end

  # Mark invitation as expired
  def expire!
    update(status: 'expired')
  end

  # Mark invitation as rejected
  def reject!
    update(status: 'rejected')
  end

  # Cancel the invitation
  def cancel!
    update(status: 'cancelled')
  end

  # Extend invitation expiration
  def extend_expiration!(days = 7)
    update(expires_at: (expires_at || Time.current) + days.days)
  end

  # Resend invitation with new token
  def resend!
    new_token = self.class.generate_token
    update(
      token: new_token,
      status: 'pending',
      expires_at: 7.days.from_now,
      accepted_at: nil
    )
  end

  # Get sender's full name
  def sender_name
    sender&.full_name || sender&.name || 'System'
  end

  # Get school name
  def school_name
    school&.schoolName || school&.name || 'Unknown School'
  end

  # Check if invitation is for multiple learners
  def multiple_learners?
    learner_ids.present? && learner_ids.size > 1
  end

  # Get count of learners
  def learner_count
    learner_ids&.size || (learner_number.present? ? 1 : 0)
  end

  # Format learner names for display
  def learner_names_display
    return 'No learners' if learner_names.blank?
    
    case learner_names.size
    when 1
      learner_names.first
    when 2
      learner_names.join(' and ')
    else
      "#{learner_names[0..-2].join(', ')}, and #{learner_names.last}"
    end
  end

  # Get primary learner (for backward compatibility)
  def primary_learner
    {
      id: learner_ids&.first,
      number: learner_numbers&.first || learner_number,
      name: learner_names&.first
    }
  end

  # Add a learner to the invitation
  def add_learner(learner_id, learner_number, learner_name)
    self.learner_ids ||= []
    self.learner_numbers ||= []
    self.learner_names ||= []
    
    unless learner_ids.include?(learner_id)
      self.learner_ids << learner_id
      self.learner_numbers << learner_number
      self.learner_names << learner_name
      
      # Set legacy field if this is the first learner
      self.learner_number = learner_number if self.learner_number.blank?
    end
    
    save
  end

  # Remove a learner from the invitation
  def remove_learner(learner_id)
    return false unless learner_ids.include?(learner_id)
    
    index = learner_ids.index(learner_id)
    self.learner_ids.delete_at(index)
    self.learner_numbers.delete_at(index)
    self.learner_names.delete_at(index)
    
    # Update legacy field if needed
    self.learner_number = learner_numbers.first if learner_number == learner_id.to_s
    
    save
  end

  # Serialize to API hash
  def to_api_hash(include_token: false)
    hash = {
      id: id.to_s,
      recipient_phone_number: recipient_phone_number,
      role: role,
      status: status,
      invited_via: invited_via,
      parent_name: parent_name,
      school_id: school_id&.to_s,
      school_name: school_name,
      sender_id: sender_id&.to_s,
      sender_name: sender_name,
      learner_number: learner_number,
      learner_numbers: learner_numbers,
      learner_ids: learner_ids,
      learner_names: learner_names,
      learner_count: learner_count,
      multiple_learners: multiple_learners?,
      grade_id: grade_id,
      accepted_at: accepted_at&.iso8601,
      expires_at: expires_at&.iso8601,
      expired: expired?,
      valid: valid_invitation?,
      invitation_type: invitation_type,
      metadata: metadata,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
    
    hash[:token] = token if include_token
    hash
  end

  # Get simplified representation for notifications
  def to_notification_hash
    {
      id: id.to_s,
      recipient_phone_number: recipient_phone_number,
      learner_names: learner_names_display,
      school_name: school_name,
      expires_at: expires_at&.strftime('%b %d, %Y'),
      invitation_link: Rails.application.routes.url_helpers.accept_invitation_url(token: token)
    }
  end

  private

  # Generate unique token
  def generate_token
    self.token = self.class.generate_token
  end

  # Set default expiration time
  def set_default_expiration
    self.expires_at ||= 7.days.from_now
  end

  # Update status if invitation has expired
  def update_status_if_expired
    if status == 'pending' && expired?
      update_columns(status: 'expired') rescue nil
    end
  end

  # Sync legacy fields with new array fields for backward compatibility
  def sync_legacy_learner_fields
    # If we have array data but no legacy field, set it from first element
    if learner_number.blank? && learner_numbers.present?
      self.learner_number = learner_numbers.first
    end
    
    # If we only have legacy field, populate arrays
    if learner_number.present? && learner_ids.blank?
      self.learner_ids = [learner_number]
      self.learner_numbers = [learner_number]
      self.learner_names = [learner_number] # Default name
    end
  end

  # Validate learner data consistency
  def validate_learner_data_consistency
    return if learner_ids.blank? && learner_number.blank?
    
    if learner_ids.present?
      # All arrays should have same length
      if learner_numbers.present? && learner_ids.length != learner_numbers.length
        errors.add(:learner_numbers, "must have same count as learner_ids")
      end
      
      if learner_names.present? && learner_ids.length != learner_names.length
        errors.add(:learner_names, "must have same count as learner_ids")
      end
    end
  end

  # Validate phone number format
  def validate_phone_number_format
    return if recipient_phone_number.blank?
    
    # Basic phone validation - adjust based on your requirements
    unless recipient_phone_number.match?(/\A\+?[\d\s\-\(\)]{10,}\z/)
      errors.add(:recipient_phone_number, "is not a valid phone number")
    end
  end
end