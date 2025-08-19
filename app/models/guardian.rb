# app/models/guardian.rb
class Guardian
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name, type: String
    field :email, type: String
    field :phone, type: String
    field :relationship, type: String
    field :is_primary, type: Boolean, default: false
    field :address, type: Hash

    belongs_to :student
    belongs_to :school

    validates :name, :relationship, presence: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
end
