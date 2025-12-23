# app/models/invitation.rb
class Invitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :token, type: String
  field :status, type: String, default: 'pending'
  field :recipient_phone_number, type: String
  field :role, type: String, default: 'parent' # Add role field
  field :invited_via, type: String, default: 'whatsapp'
  field :learner_number, type: String
  field :learner_ids, type: Array, default: []
  field :learner_names, type: Array, default: []
  field :parent_name, type: String
  field :grade_id, type: String

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User'
  belongs_to :school

  # ===================== VALIDATIONS ======================
  validates :recipient_phone_number, presence: true
  validates :token, presence: true, uniqueness: true
  validates :role, presence: true

  # ======================= INDEXES ========================
  index({ token: 1 }, { unique: true })
  index({ status: 1 })
  index({ role: 1 })
  index({ learner_ids: 1 })
end
