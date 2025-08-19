class Payment
    include Mongoid::Document
    include Mongoid::Timestamps

    # Fields
    field :amount, type: Float
    field :payment_method, type: String # 'credit_card', 'bank_transfer', 'mobile_money', 'cash'
    field :transaction_id, type: String
    field :description, type: String
    field :status, type: String, default: "completed" # 'pending', 'completed', 'failed', 'refunded'
    field :metadata, type: Hash, default: {}

    # Associations
    belongs_to :account, class_name: "Account", inverse_of: :payments
    belongs_to :school, class_name: "School", inverse_of: :payments
    belongs_to :user, class_name: "User", inverse_of: :payments

    # Validations
    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :payment_method, presence: true
    validates :account_id, presence: true
    validates :school_id, presence: true
    validates :user_id, presence: true

    # Callbacks
    before_create :process_payment
    after_create :update_account_balance

    # Scopes
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :by_school, ->(school_id) { where(school_id: school_id) }
    scope :by_account, ->(account_id) { where(account_id: account_id) }

    private

    def process_payment
      # In a real app, this would interface with a payment processor
      self.status = "completed"
      self.transaction_id ||= "pay_#{SecureRandom.hex(10)}"
    end

    def update_account_balance
      account.add_payment(amount, payment_method, description)
      school.deduct_funds(amount) if status == "completed"
    end
end
