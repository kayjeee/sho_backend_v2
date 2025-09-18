class Invite
  include Mongoid::Document
  include Mongoid::Timestamps

  # Fields
  field :pr_code, type: String
  field :recipient_type, type: String # learner, parent, teacher
  field :recipient_name, type: String
  field :recipient_email, type: String
  field :recipient_phone, type: String
  field :invite_link, type: String
  field :qr_code_data, type: String
  field :channels, type: Array, default: [] # e.g. whatsapp, sms, email
  field :custom_message, type: String
  field :status, type: String, default: 'pending' # pending, sent, viewed, accepted, expired
  field :expires_at, type: DateTime
  field :accepted_at, type: DateTime       # Added accepted_at field
  field :view_count, type: Integer, default: 0
  field :last_viewed_at, type: DateTime

  # Metadata for additional info, flexible
  field :metadata, type: Hash, default: {}

  # Associations
  belongs_to :school
  belongs_to :user  # The user who created the invite

  # Validations
  validates :pr_code, presence: true, uniqueness: true
  validates :recipient_type, presence: true, inclusion: { in: %w(learner parent teacher) }
  validates :status, presence: true, inclusion: { in: %w(pending sent viewed accepted expired) }
  validates :recipient_email, format: { with: URI::MailTo::EMAIL_REGEXP }, if: -> { recipient_email.present? }

  # Indexes
  index({ pr_code: 1 }, { unique: true })
  index({ status: 1 })
  index({ school_id: 1 })
  index({ recipient_email: 1 })

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :expired, -> { where(:expires_at.lt => Time.current) }
  scope :not_expired, -> { any_of({ expires_at: nil }, { :expires_at.gt => Time.current }) }

  # Instance Methods
  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def accept!
    update(status: 'accepted', accepted_at: Time.current)
  end

  def view!
    self.inc(view_count: 1)
    update(last_viewed_at: Time.current)
  end
end
