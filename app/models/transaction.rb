class Transaction
  include Mongoid::Document
  include Mongoid::Timestamps

  field :amount, type: Float
  field :transaction_type, type: String # credit or debit
  field :description, type: String

  belongs_to :account

  validates :amount, presence: true
  validates :transaction_type, inclusion: { in: %w[credit debit] }
end
