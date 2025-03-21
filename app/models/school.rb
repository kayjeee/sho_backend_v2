class School
   # Fields
    include Mongoid::Document
    include Mongoid::Timestamps # Adds created_at and updated_at fields automatically

    

  field :user_id, type: String
  field :user_email, type: String
  field :schoolName, type: String
  field :schoolEmail, type: String
  field :country, type: String
  field :city, type: String
  field :province, type: String
  field :latitude, type: String
  field :longitude, type: String
  field :facebook, type: String
  field :linkedin, type: String
  field :tiktok, type: String
  field :theme, type: String
  field :website, type: String
  field :logo, type: String
  field :schoolAddress, type: Hash
# Scope to filter schools by user_id
scope :by_user, ->(user_id) { where(user_id: user_id) }
    # Embeds Many: Access Requests
    embeds_many :access_requests, class_name: 'AccessRequest'
  
    # Embeds Many: Messages
    embeds_many :messages, class_name: 'Message'
  
    # Validations
    validates :schoolName, presence: true
    validates :schoolEmail, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    # Example scope
    scope :by_city, ->(city) { where(City: city) }
  end
  
  # Embedded AccessRequest model
  class AccessRequest
    include Mongoid::Document
  
    field :loggedInUserEmail, type: String
    field :reason, type: String
    field :requestedAt, type: DateTime
    field :acceptedBy, type: String
    field :status, type: String
  
    embedded_in :school
  end
  
  # Embedded Message model
  class Message
    include Mongoid::Document
  
    field :messageId, type: BSON::ObjectId
    field :sender, type: String
    field :message, type: String
    field :timestamp, type: DateTime
    field :parentEmail, type: String
  
    embedded_in :school
  end
  