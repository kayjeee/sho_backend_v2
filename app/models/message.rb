class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content, type: String
  field :school_id, type: BSON::ObjectId
  field :user_id, type: BSON::ObjectId
  field :schoolName, type:String
  field :name,  type:String
  field :read, type: Boolean, default: false
  field :sender_id, type: BSON::ObjectId
  
    belongs_to :user, class_name: 'User', inverse_of: :conversations
    belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true
    belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages


   # Validations
   validates :content, presence: true

   after_create_commit :broadcast_to_participants

   private

   def broadcast_to_participants
     MessagesChannel.broadcast_to(
       conversation,
       serialize_message
     )
   end

   def serialize_message
     {
       id:        id.to_s,
       content:   content,
       sender_id: user_id&.to_s || school_id&.to_s,
       timestamp: created_at,
       read:      read,
       name:      name,
       schoolName: schoolName
     }
   end
end
