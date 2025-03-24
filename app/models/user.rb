class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :email, type: String
  field :auth0_id, type: String
  field :roles, type: Array, default: []
  field :cash_account, type: Float, default: 0.0 # Add cash account
  field :payment_history, type: Array, default: [] # Add payment history

  validates :auth0_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
  # Association with conversations
  has_many :conversations, foreign_key: :user_id
    # Association for messages sent by the user
    has_many :sent_messages, class_name: 'Message', inverse_of: :sender
    has_many :messages, inverse_of: :user
    # Association for messages received by the user
    has_many :received_messages, class_name: 'Message', inverse_of: :receiver
end