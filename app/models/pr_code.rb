class PrCode
  include Mongoid::Document
  include Mongoid::Timestamps

  field :code, type: String
  field :status, type: String, default: 'active' # active, redeemed, expired
  field :recipient_type, type: String # learner, parent, teacher
  field :expires_at, type: DateTime

  belongs_to :invite
  belongs_to :school

  validates :code, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w(active redeemed expired) }

  index({ code: 1 }, { unique: true })
  index({ school_id: 1, status: 1 })
end
