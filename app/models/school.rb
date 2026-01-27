class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # Basic Information
  field :schoolName, type: String
  field :schoolEmail, type: String
  
  # Location
  field :country, type: String
  field :city, type: String
  field :province, type: String
  field :latitude, type: Float
  field :longitude, type: Float
  
  # Address
  field :line1, type: String
  field :line2, type: String
  field :postalCode, type: String
  
  # Social Media
  field :facebook, type: String
  field :linkedin, type: String
  field :tiktok, type: String
  field :website, type: String
  
  # Branding
  field :logo, type: String
  field :theme, type: String, default: ""  # Changed to String
  
  # Financial
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []
  
  # Users & Invitations
  field :adminUsers, type: Array, default: []
  field :invites, type: Array, default: []
  
  # Status & Metadata
  field :status, type: String, default: "active"
  field :user_id, type: String
  field :user_email, type: String
  field :school_created_by, type: String
  
  # Validations
  validates :schoolName, presence: true, uniqueness: true
  validates :schoolEmail, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :country, presence: true
  
  # Indexes
  index({ schoolName: 1 }, { unique: true })
  index({ schoolEmail: 1 })
  index({ status: 1 })
  index({ user_id: 1 })
  index({ created_at: -1 })
end