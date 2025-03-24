class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content, type: String
  field :school_id, type: BSON::ObjectId
  field :user_id, type: BSON::ObjectId
  field :schoolName, type:String
  field :name,  type:String
  
    belongs_to :user, class_name: 'User', inverse_of: :conversations
    belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true
    belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages


   # Validations
   validates :content, presence: true
   
end
