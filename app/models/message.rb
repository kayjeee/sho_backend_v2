class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content, type: String
  field :school_id, type: BSON::ObjectId
  field :user_id, type: BSON::ObjectId
  field :schoolName, type: String
  field :name, type: String
  field :is_read, type: Boolean, default: false
  field :reactions, type: Hash, default: {}
  field :pinned, type: Boolean, default: false
  field :starred_by, type: Array, default: []

  belongs_to :user, class_name: 'User', inverse_of: :conversations, optional: true
  belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true
  belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages


  # Validations
  validates :content, presence: true

  index({ content: "text" })
end
