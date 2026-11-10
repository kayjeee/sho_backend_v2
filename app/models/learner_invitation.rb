# app/models/learner_invitation.rb
class LearnerInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :learner_email,         type: String
  field :learner_phone,         type: String
  field :invitation_token,      type: String
  field :status,                type: Integer, default: 0
  field :invitation_data,       type: Hash, default: {}
  field :invited_at,            type: DateTime
  field :expires_at,            type: DateTime
  field :accepted_at,           type: DateTime

  # ===================== CONSTANTS =======================
  STATUSES = {
    'pending' => 0,
    'accepted' => 1,
    'declined' => 2,
    'expired' => 3,
    'cancelled' => 4
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :invitation_token,  presence: true, uniqueness: true
  validates :status,            inclusion: { in: STATUSES.values }
  validates :learner_email,     format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :expires_at,        presence: true
  validates :grade_id,          presence: true
  validates :invited_by_id,     presence: true

  validate :email_or_phone_present
  validate :expiration_date_future

  # ===================== ASSOCIATIONS =====================
  belongs_to :grade,            class_name: 'Grade'
  belongs_to :invited_by,       class_name: 'User'
  belongs_to :learner,          class_name: 'Learner', optional: true

  # ======================== INDEXES =======================
  index({ invitation_token: 1 }, { unique: true })
  index({ grade_id: 1, status: 1 })
  index({ expires_at: 1 })
  index({ learner_email: 1 })

  # ========================= SCOPES ========================
  scope :pending,               -> { where(status: 0) }
  scope :accepted,              -> { where(status: 1) }
  scope :declined,              -> { where(status: 2) }
  scope :expired,               -> { where(status: 3) }
  scope :cancelled,             -> { where(status: 4) }
  scope :active,                -> { where(status: [0, 1]) }
  scope :by_grade,              ->(grade_id) { where(grade_id: grade_id) }
  scope :expiring_soon,         -> { pending.where(:expires_at.lte => 24.hours.from_now) }

  # ======================== CALLBACKS =======================
  before_validation :generate_token, if: -> { invitation_token.blank? }
  before_validation :set_invited_at, if: -> { invited_at.blank? }
  before_validation :set_expiration, if: -> { expires_at.blank? }
  before_save :check_expiration

  # ========================= METHODS ========================

  # Status helper methods
  def pending?
    status == 0
  end

  def accepted?
    status == 1
  end

  def declined?
    status == 2
  end

  def expired?
    status == 3 || expires_at < Time.current
  end

  def cancelled?
    status == 4
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  # Invitation actions
  def accept!(learner_params = {})
    return false unless pending? && !expired?

    transaction do
      # Create or update learner
      if learner.present?
        learner.update!(learner_params) if learner_params.any?
      else
        learner_data = {
          grade: grade,
          school: grade.school,
          created_by: invited_by,
          **learner_params
        }
        self.learner = Learner.create!(learner_data)
      end

      update!(
        status: 1,
        accepted_at: Time.current
      )

      Rails.logger.info "✅ Learner invitation accepted: #{invitation_token} for grade #{grade.name}"
      true
    end
  rescue => e
    Rails.logger.error "❌ Failed to accept invitation #{invitation_token}: #{e.message}"
    false
  end

  def decline!(reason = nil)
    return false unless pending?

    update!(
      status: 2,
      invitation_data: invitation_data.merge(declined_reason: reason)
    )

    Rails.logger.info "❌ Learner invitation declined: #{invitation_token} for grade #{grade.name}"
    true
  end

  def cancel!(reason = nil)
    return false unless pending?

    update!(
      status: 4,
      invitation_data: invitation_data.merge(cancelled_reason: reason)
    )

    Rails.logger.info "🚫 Learner invitation cancelled: #{invitation_token} for grade #{grade.name}"
    true
  end

  # Utility methods
  def days_until_expiry
    return 0 if expired?
    ((expires_at - Time.current) / 1.day).ceil
  end

  def contact_info
    learner_email.presence || learner_phone.presence
  end

  def invitation_url
    # This would generate the actual invitation URL for your frontend
    Rails.application.routes.url_helpers.accept_learner_invitation_url(
      token: invitation_token,
      host: Rails.application.config.app_host
    )
  rescue
    nil
  end

  def to_api_hash
    {
      id: id.to_s,
      invitation_token: invitation_token,
      learner_email: learner_email,
      learner_phone: learner_phone,
      status: status,
      status_text: status_text,
      grade: {
        id: grade_id.to_s,
        name: grade&.name,
        school_name: grade&.school&.schoolName
      },
      invited_by: {
        id: invited_by_id.to_s,
        name: invited_by&.name
      },
      learner: learner&.to_api_hash,
      invited_at: invited_at,
      expires_at: expires_at,
      accepted_at: accepted_at,
      days_until_expiry: days_until_expiry,
      invitation_data: invitation_data,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def generate_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end

  def set_invited_at
    self.invited_at = Time.current
  end

  def set_expiration
    self.expires_at = 7.days.from_now
  end

  def check_expiration
    if pending? && expires_at < Time.current
      self.status = 3  # expired
    end
  end

  def email_or_phone_present
    if learner_email.blank? && learner_phone.blank?
      errors.add(:base, "Either email or phone number must be provided")
    end
  end

  def expiration_date_future
    return unless expires_at

    if expires_at < Time.current
      errors.add(:expires_at, "must be in the future")
    end
  end
end