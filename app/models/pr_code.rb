# app/models/pr_code.rb
class PrCode
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String
  field :purpose, type: String
  field :status, type: String, default: 'active'
  field :expires_at, type: DateTime
  field :used_at, type: DateTime, default: nil
  field :metadata, type: Hash, default: {}

  belongs_to :school
  belongs_to :user, optional: true

  validates :code, presence: true, uniqueness: { scope: :school_id }
  validates :purpose, presence: true
  validates :expires_at, presence: true
  validates :status, inclusion: { in: %w[active used expired revoked] }

  scope :active, -> { where(status: 'active').where('expires_at > ?', Time.current) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_purpose, ->(purpose) { where(purpose: purpose) }

  before_validation :set_default_expiration, on: :create

  def expired?
    expires_at < Time.current
  end

  def mark_used!(user = nil)
    update!(
      status: 'used',
      used_at: Time.current,
      user: user
    )
  end

  def revoke!
    update!(status: 'revoked')
  end

  private

  def set_default_expiration
    self.expires_at ||= 24.hours.from_now
  end
end