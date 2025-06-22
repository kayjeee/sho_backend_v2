class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :email, type: String
  field :auth0_id, type: String
  field :roles, type: Array, default: []
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []

  validates :auth0_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true

  # Association with conversations
  has_many :conversations, foreign_key: :user_id

  has_many :accounts, class_name: 'Account', inverse_of: :user
  # Association for messages sent by the user
  has_many :sent_messages, class_name: 'Message', inverse_of: :sender
  has_many :messages, inverse_of: :user

  # Association for messages received by the user
  has_many :received_messages, class_name: 'Message', inverse_of: :receiver

  # Association with UserSchoolRole as the join table
  has_many :user_school_roles, class_name: 'UserSchoolRole', inverse_of: :user

  # Schools related through UserSchoolRole (acts as a join model)
  has_and_belongs_to_many :schools, class_name: 'School', inverse_of: :users, validate: false
end
