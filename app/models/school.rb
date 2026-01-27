# app/models/school.rb
class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # =========================================================
  # CORE SCHOOL INFO
  # =========================================================
  field :schoolName,   type: String
  field :schoolEmail,  type: String
  field :logo,         type: String
  field :website,      type: String
  field :theme,        type: String
  field :status,       type: String, default: "active"

  # =========================================================
  # ADDRESS (FLATTENED)
  # =========================================================
  field :line1,        type: String
  field :line2,        type: String
  field :city,         type: String
  field :province,     type: String
  field :country,      type: String
  field :postalCode,   type: String

  # =========================================================
  # LOCATION COORDINATES
  # =========================================================
  field :latitude,     type: Float
  field :longitude,    type: Float

  # =========================================================
  # SOCIAL LINKS
  # =========================================================
  field :facebook,     type: String
  field :linkedin,     type: String
  field :tiktok,       type: String

  # =========================================================
  # FINANCIAL
  # =========================================================
  field :cash_account,    type: Float, default: 0.0
  field :payment_history, type: Array, default: []

  # =========================================================
  # USER / OWNERSHIP
  # =========================================================
  field :user_id,            type: String
  field :user_email,         type: String
  field :school_created_by,  type: String

  # Admin & invite tracking
  field :adminUsers, type: Array, default: []
  field :invites,    type: Array, default: []

  # =========================================================
  # ASSOCIATIONS
  # =========================================================
  has_many :grades, class_name: "Grade", inverse_of: :school
  has_many :pr_codes, dependent: :destroy

  # =========================================================
  # VALIDATIONS
  # =========================================================
  validates :schoolName,
            presence: true,
            uniqueness: true

  validates :schoolEmail,
            presence: true,
            uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  # =========================================================
  # INDEXES
  # =========================================================
  index({ schoolName: 1 },  unique: true, name: "school_name_index")
  index({ schoolEmail: 1 }, unique: true, name: "school_email_index")
  index({ user_id: 1 },     name: "user_id_index")
  index(
    { country: 1, province: 1, city: 1 },
    name: "location_index"
  )
end
