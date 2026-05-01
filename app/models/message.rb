class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content,     type: String
  field :sender_id,   type: BSON::ObjectId
  field :user_id,     type: BSON::ObjectId
  field :school_id,   type: BSON::ObjectId
  field :schoolName,  type: String
  field :name,        type: String
  field :read,        type: Boolean, default: false

  belongs_to :user, class_name: 'User', inverse_of: :conversations
  belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true
  belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages

  # Validations
  validates :content, presence: true

  # FIX: Mongoid 9 does NOT support after_create_commit :method_name
  # You must use a block instead
  after_create do |doc|
    MessagesChannel.broadcast_to(
      doc.conversation,
      MessageSerializer.new(doc).as_json
    )
  end
end
