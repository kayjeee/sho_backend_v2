class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # Fields
  field :user_id, type: String
  field :user_email, type: String
  field :school_created_by, type: String
  field :schoolName, type: String
  field :schoolEmail, type: String
  field :country, type: String
  field :city, type: String
  field :province, type: String
  field :latitude, type: String
  field :longitude, type: String
  field :facebook, type: String
  field :linkedin, type: String
  field :tiktok, type: String
  field :theme, type: String
  field :website, type: String
  field :logo, type: String
  field :schoolAddress, type: Hash
  field :cash_account, type: Float, default: 0.0 # Add cash account
  field :payment_history, type: Array, default: [] # Add payment history

  # Associations
  has_many :user_school_roles, class_name: 'UserSchoolRole', inverse_of: :school
  # Relationships
  has_many :access_requests, class_name: 'RequestAccess', inverse_of: :school
  has_many :admin_users, class_name: 'AdminUser', inverse_of: :school
  has_many :conversations, class_name: 'Conversation', inverse_of: :school

  # Validations
  validates :schoolName, presence: true
  validates :schoolEmail, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Callbacks
  before_create :set_school_created_by

  # Scopes
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_city, ->(city) { where(city: city) }

  private

  def set_school_created_by
    self.school_created_by = user_email
  end
end

class UserSchoolRole
  include Mongoid::Document

  # Fields
  field :user_id, type: String
  field :role, type: String # Define role of the user

  # Associations
  belongs_to :school
  belongs_to :user # Assuming a User model exists

  # Validations
  validates :user_id, presence: true
  validates :role, presence: true
end
