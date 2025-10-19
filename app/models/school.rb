class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # Core school information
  field :schoolName, type: String
  field :schoolEmail, type: String
  field :logo, type: String
  
  # Address fields
  field :line1, type: String
  field :line2, type: String
  field :country, type: String
  field :province, type: String
  field :city, type: String
  field :postalCode, type: String

  # Location coordinates
  field :latitude, type: Float
  field :longitude, type: Float

  # Theme and branding
  field :theme, type: String
  field :website, type: String

  # Social media links
  field :facebook, type: String
  field :tiktok, type: String
  field :linkedin, type: String

  # Financial fields
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []

  # User info
  field :user_id, type: String
  field :user_email, type: String
  field :school_created_by, type: String

  # Embedded documents for admins and invites
  field :adminUsers, type: Array, default: []
  field :invites, type: Array, default: []
  field :status, type: String, default: "active"
  # Associations
  has_many :grades, class_name: 'Grade', inverse_of: :school
  has_many :students, class_name: 'Student', inverse_of: :school
  has_many :pr_codes, dependent: :destroy

  # Validations
  validates :schoolName, presence: true, uniqueness: true
  validates :schoolEmail, presence: true, uniqueness: true

  # Indexes
  index({ schoolName: 1 }, { unique: true, name: "school_name_index" })
  index({ schoolEmail: 1 }, { unique: true, name: "school_email_index" })
  index({ user_id: 1 }, { name: "user_id_index" })
  index({ country: 1, province: 1, city: 1 }, { name: "location_index" })
end
