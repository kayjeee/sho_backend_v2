# app/models/account.rb
class Account
    include Mongoid::Document
    include Mongoid::Timestamps
  
    field :balance, type: Float, default: 0.0
    field :status, type: String, default: 'active' # active, overdue, frozen
    field :last_payment_date, type: DateTime
    field :payment_history, type: Array, default: []
    field :credit_limit, type: Float, default: 0.0
    field :payment_methods, type: Array, default: []
  
    belongs_to :student
    belongs_to :school
    has_many :transactions
  
    validates :balance, numericality: true
    validates :status, inclusion: { in: %w[active overdue frozen] }
  
    def update_balance(amount)
      update(balance: balance + amount)
    end
  end