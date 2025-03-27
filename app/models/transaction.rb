class Transaction
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # Status Constants (added new statuses while keeping existing ones)
  STATUSES = %w[pending completed failed refunded void].freeze
  TYPES = %w[payment refund adjustment fee].freeze

  # Existing Fields (kept exactly as is)
  field :user_id, type: String
  field :school_id, type: String
  field :amount, type: Float
  field :status, type: String, default: 'pending' # Can be 'pending', 'completed', 'failed'
  field :payment_gateway_response, type: Hash # Store payment gateway response for auditing

  # New Fields (additions)
  field :transaction_type, type: String, default: 'payment'
  field :reference_number, type: String
  field :description, type: String
  field :payment_method, type: String
  field :metadata, type: Hash
  field :processed_at, type: DateTime
  field :initiated_by_id, type: String
  field :student_id, type: String
  field :account_id, type: String

  # Validations (existing + new)
  validates :user_id, presence: true
  validates :school_id, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :transaction_type, inclusion: { in: TYPES }, allow_nil: true
  validates :reference_number, uniqueness: true, allow_nil: true

  # Associations (new)
  belongs_to :school
  belongs_to :user
  belongs_to :student, optional: true
  belongs_to :account, optional: true
  belongs_to :initiated_by, class_name: 'User', foreign_key: :initiated_by_id, optional: true

  # Callbacks (enhanced existing callback)
  before_create :generate_reference_number
  after_save :update_user_and_school_accounts
  after_save :update_account_balance, if: :status_changed_to_completed?

  # Scopes (new)
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_school, ->(school_id) { where(school_id: school_id) }
  scope :for_student, ->(student_id) { where(student_id: student_id) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods (new)
  def complete!
    update(status: 'completed', processed_at: Time.current)
  end

  def fail!(error_message = nil)
    update(status: 'failed', payment_gateway_response: { error: error_message })
  end

  def formatted_amount
    amount.positive? ? "+#{amount}" : amount.to_s
  end

  private

  # Existing callback (unchanged)
  def update_user_and_school_accounts
    if status == 'completed'
      user = User.find(user_id)
      school = School.find(school_id)

      # Deduct amount from user's cash account
      user.update(cash_account: user.cash_account - amount)

      # Add amount to school's cash account
      school.update(cash_account: school.cash_account + amount)

      # Add transaction to user's and school's payment history
      user.payment_history << { transaction_id: id, amount: amount, date: created_at }
      school.payment_history << { transaction_id: id, amount: amount, date: created_at }

      user.save
      school.save
    end
  end

  # New callback for account balance updates
  def update_account_balance
    return unless account_id.present? && account

    account.update_balance(amount)
    account.payment_history << {
      transaction_id: id,
      amount: amount,
      date: processed_at || created_at,
      type: amount.positive? ? 'credit' : 'debit'
    }
    account.save
  end

  def status_changed_to_completed?
    status_changed? && status == 'completed'
  end

  def generate_reference_number
    self.reference_number ||= "TXN-#{Time.now.to_i}-#{SecureRandom.hex(4).upcase}"
  end
end