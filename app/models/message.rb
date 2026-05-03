class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content,    type: String
  field :sender_id,  type: String   # store as String, not BSON::ObjectId
  field :user_id,    type: String   # easier comparison with current_user.id.to_s
  field :school_id,  type: String
  field :schoolName, type: String
  field :name,       type: String
  field :read,       type: Boolean, default: false

  belongs_to :school,       class_name: 'School',       inverse_of: :messages,          optional: true, primary_key: :id, foreign_key: :school_id
  belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages
  belongs_to :sender,       class_name: 'User',         inverse_of: :sent_messages,     optional: true, primary_key: :id, foreign_key: :sender_id
  belongs_to :receiver,     class_name: 'User',         inverse_of: :received_messages, optional: true, primary_key: :id, foreign_key: :receiver_id

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
