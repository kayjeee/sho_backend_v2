# app/models/pr_code.rb
class PrCode < ApplicationRecord
  belongs_to :school
  belongs_to :user, optional: true

  validates :code, presence: true, uniqueness: true
  validates :purpose, presence: true
  validates :expires_at, presence: true

  # FIXED: Proper enum syntax for Rails
  enum :status, {
    active: 'active',
    used: 'used', 
    expired: 'expired',
    revoked: 'revoked'
  }, default: :active

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