# app/models/account.rb
class Account
  include Mongoid::Document
  include Mongoid::Timestamps

  # Fields
  field :status, type: String, default: 'active' # 'active', 'inactive', 'suspended', 'overdue'
  field :balance, type: Float, default: 0.0
  field :payment_history, type: Array, default: []
  field :account_type, type: String # 'parent' or 'student'
  
  # New fields for debt management
  field :due_date, type: Date
  field :days_overdue, type: Integer, default: 0
  field :last_payment_date, type: Date
  field :credit_limit, type: Float, default: 0.0
  field :notes, type: String
  field :minimum_payment, type: Float, default: 0.0
  field :last_reminder_sent, type: DateTime

  # Associations
  belongs_to :user, class_name: 'User', inverse_of: :accounts
  belongs_to :school, class_name: 'School', inverse_of: :accounts
  has_many :payments, class_name: 'Payment', inverse_of: :account

  # Validations
  validates :user_id, presence: true
  validates :school_id, presence: true
  validates :account_type, inclusion: { in: %w[parent student] }
  validates :status, inclusion: { in: %w[active inactive suspended overdue] }
  validates :balance, numericality: { greater_than_or_equal_to: 0 }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :parents, -> { where(account_type: 'parent') }
  scope :students, -> { where(account_type: 'student') }
  scope :overdue, -> { where(status: 'overdue') }
  scope :with_balance, -> { where(:balance.gt => 0) }
  scope :due_this_week, -> { where(due_date: Date.current..(Date.current + 7.days)) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }

  # Indexes
  index({ school_id: 1, account_type: 1 })
  index({ school_id: 1, _id: 1 })
  index({ school_id: 1, status: 1 })
  index({ user_id: 1, status: 1 })
  index({ due_date: 1 })

  # Callbacks
  before_save :update_days_overdue
  before_save :update_last_payment_date
  before_save :update_account_status

  # Instance methods

  # Add a payment to the account
  def add_payment(amount, method, description = '')
    self.balance -= amount
    payment_record = {
      id: SecureRandom.uuid,
      amount: amount,
      date: Time.current,
      method: method,
      description: description,
      balance_after: balance,
      processed_by: User.current_user.try(:id) # Assuming you have current_user
    }
    self.payment_history.unshift(payment_record)
    save
    payment_record
  end

  # Add a charge to the account
  def add_charge(amount, description = '')
    self.balance += amount
    charge_record = {
      id: SecureRandom.uuid,
      amount: amount,
      date: Time.current,
      description: description,
      balance_after: balance,
      type: 'charge'
    }
    self.payment_history.unshift(charge_record)
    save
    charge_record
  end

  # Update account status based on balance and due date
  def update_status
    if balance <= 0
      self.status = 'active'
    elsif due_date.present? && due_date < Date.current
      self.status = 'overdue'
    else
      self.status = 'active'
    end
    save
  end

  # Check if account is overdue
  def overdue?
    status == 'overdue' || (due_date.present? && due_date < Date.current && balance > 0)
  end

  # Calculate days overdue
  def calculate_days_overdue
    return 0 unless due_date.present? && balance > 0
    (Date.current - due_date).to_i
  end

  # Get last payment amount
  def last_payment_amount
    last_payment = payment_history.select { |p| p['amount'].positive? }.first
    last_payment ? last_payment['amount'] : 0
  end

  private

  def update_days_overdue
    self.days_overdue = calculate_days_overdue if overdue?
  end

  def update_last_payment_date
    last_payment = payment_history.select { |p| p['amount'].positive? }.first
    self.last_payment_date = last_payment[:date] if last_payment
  end

  def update_account_status
    self.status = if balance <= 0
                   'active'
                 elsif due_date.present? && due_date < Date.current
                   'overdue'
                 else
                   'active'
                 end
  end
end