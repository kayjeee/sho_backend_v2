class User
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :email, type: String
  field :auth0_id, type: String
  field :roles, type: Array, default: []

  validates :auth0_id, presence: true, uniqueness: true
  validates :email, presence: true, uniqueness: true
end