class AdminUser
    include Mongoid::Document
    include Mongoid::Timestamps

    # Fields
    field :invited_by, type: String
    field :date_invited, type: DateTime
    field :admin_user_email, type: String
    field :admin_user_schoolname, type: String
    field :admin_user_roles, type: Array, default: []
    field :school_id, type: String

    # Relationships
    belongs_to :school, class_name: "School", inverse_of: :admin_users

    # Validations
    validates :admin_user_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :admin_user_roles, presence: true
    validates :school, presence: true # Ensures each AdminUser belongs to one School
  # Association for messages sent by the user
  has_many :sent_messages, class_name: "Message", inverse_of: :sender

  # Association for messages received by the user
  has_many :received_messages, class_name: "Message", inverse_of: :receiver
end
