class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # Fields (keeping all your existing fields)
  field :user_id, type: String
  field :user_email, type: String
  field :school_created_by, type: String
  field :schoolName, type: String # Keeping original field name for frontend compatibility
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
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []

  # New fields for account management
  field :features, type: Hash, default: -> {
    {
      online_payments: true,
      meal_pre_ordering: false,
      event_management: true,
      attendance_tracking: false,
      gradebook: true
    }
  }
  
  field :branding, type: Hash, default: -> {
    {
      primary_color: '#3b82f6',
      secondary_color: '#10b981',
      logo: nil,
      theme: 'light'
    }
  }

  # Associations (keeping existing and adding new ones)
  has_many :user_school_roles, class_name: 'UserSchoolRole', inverse_of: :school
  has_many :access_requests, class_name: 'RequestAccess', inverse_of: :school
  has_many :admin_users, class_name: 'AdminUser', inverse_of: :school
  has_many :conversations, class_name: 'Conversation', inverse_of: :school
  
  # New associations for account management
  has_many :students, class_name: 'Student', inverse_of: :school
  has_many :accounts, class_name: 'Account', inverse_of: :school
  has_many :transactions, class_name: 'Transaction', inverse_of: :school
  has_many :events, class_name: 'Event', inverse_of: :school
  has_many :trips, class_name: 'Trip', inverse_of: :school

  # Validations (keeping existing)
  validates :schoolName, presence: true
  validates :schoolEmail, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  # Callbacks (keeping existing)
  before_create :set_school_created_by

  # Scopes (keeping existing)
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_city, ->(city) { where(city: city) }

  # New scopes for account management
  scope :with_overdue_accounts, -> { where(:accounts.elem_match => { status: 'overdue' }) }
  scope :with_active_accounts, -> { where(:accounts.elem_match => { status: 'active' }) }

  # Instance methods for financial operations
  def add_funds(amount)
    increment(cash_account: amount)
    payment_history << { amount: amount, date: Time.current, type: 'credit' }
    save
  end

  def deduct_funds(amount)
    decrement(cash_account: amount)
    payment_history << { amount: amount, date: Time.current, type: 'debit' }
    save
  end

  def total_outstanding_balance
    accounts.sum(:balance)
  end

  def overdue_balance
    accounts.where(status: 'overdue').sum(:balance)
  end

  private

  def set_school_created_by
    self.school_created_by = user_email
  end
end