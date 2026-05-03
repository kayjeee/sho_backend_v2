class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content,     type: String
  field :sender_id,   type: String
  field :receiver_id, type: String
  field :user_id,     type: String
  field :school_id,   type: String
  field :schoolName,  type: String
  field :name,        type: String
  field :read,        type: Boolean, default: false

  belongs_to :school,       class_name: 'School',       inverse_of: :messages, optional: true
  belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages

  # Validations
  validates :content,      presence: true
  validates :sender_id,    presence: true
  validates :conversation, presence: true

  # FIX: Mongoid 9 does NOT support after_create_commit :method_name
  # You must use a block instead
  after_create do |doc|
    MessagesChannel.broadcast_to(
      doc.conversation,
      MessageSerializer.new(doc).as_json
    )
  end
end
