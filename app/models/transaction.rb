class Transaction
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  STATUSES = %w[pending completed failed refunded void].freeze
  TYPES = %w[payment refund adjustment fee].freeze

  # Fields
  field :user_id, type: String
  field :school_id, type: String
  field :student_id, type: String
  field :account_id, type: String
  field :amount, type: Float
  field :status, type: String, default: 'pending'
  field :transaction_type, type: String, default: 'payment'
  field :reference_number, type: String
  field :description, type: String
  field :payment_method, type: String
  field :payment_gateway_response, type: Hash
  field :metadata, type: Hash
  field :processed_at, type: DateTime
  field :initiated_by_id, type: String

  # Associations
  belongs_to :school
  belongs_to :user
  belongs_to :student, optional: true
  belongs_to :account, optional: true
  belongs_to :initiated_by, class_name: 'User', foreign_key: :initiated_by_id, optional: true

  # Validations
  validates :user_id, :school_id, :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :transaction_type, inclusion: { in: TYPES }, allow_nil: true
  validates :reference_number, uniqueness: true, allow_nil: true

  # Callbacks
  before_create :generate_reference_number
  after_save :update_user_and_school_accounts
  after_save :update_account_balance, if: :completed?

  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_school, ->(school_id) { where(school_id: school_id) }
  scope :for_student, ->(student_id) { where(student_id: student_id) }
  scope :recent, -> { order(created_at: :desc) }

  # Methods
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

  def completed?
    status == 'completed'
  end

  def generate_reference_number
    self.reference_number ||= "TXN-#{Time.now.to_i}-#{SecureRandom.hex(4).upcase}"
  end

  def update_user_and_school_accounts
    return unless completed?

    user = User.find(user_id)
    school = School.find(school_id)

    user.update(cash_account: user.cash_account - amount)
    school.update(cash_account: school.cash_account + amount)

    user.payment_history << { transaction_id: id, amount: amount, date: created_at }
    school.payment_history << { transaction_id: id, amount: amount, date: created_at }

    user.save
    school.save
  end

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
end
