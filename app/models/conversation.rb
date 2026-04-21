class Conversation
  include Mongoid::Document
  include Mongoid::Timestamps

  field :participant_ids, type: Array, default: []
  field :school_id, type: BSON::ObjectId
  field :user_id, type: BSON::ObjectId

  belongs_to :user, class_name: 'User', inverse_of: :conversations
  belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true

  has_many :messages, class_name: 'Message', inverse_of: :conversation

  index({ participant_ids: 1 })
  index({ school_id: 1 })
  index({ user_id: 1 })
end
