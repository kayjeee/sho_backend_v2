# app/models/invitation.rb
class Invitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :token, type: String
  field :status, type: String, default: 'pending'
  field :recipient_phone_number, type: String

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User'
  belongs_to :school

  # ===================== VALIDATIONS ======================
  validates :recipient_phone_number, presence: true
  validates :token, presence: true, uniqueness: true

  # ======================= INDEXES ========================
  index({ token: 1 }, { unique: true })
  index({ status: 1 })
end
