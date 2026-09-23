class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  field :content,      type: String
  field :school_id,    type: BSON::ObjectId
  field :user_id,      type: BSON::ObjectId
  field :schoolName,   type: String
  field :name,         type: String
  field :sent_as_role, type: String

  belongs_to :user,         class_name: 'User', inverse_of: :conversations, optional: true
  belongs_to :school,       class_name: 'School', inverse_of: :conversations, optional: true
  belongs_to :conversation, class_name: 'Conversation', inverse_of: :messages

  # Validations
  validates :content, presence: true

  def to_api_hash
    {
      id: id.to_s,
      conversation_id: conversation_id&.to_s,
      user_id: user_id&.to_s,
      school_id: school_id&.to_s,
      content: content,
      sent_as_role: sent_as_role,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  def as_json(options = {})
    json = super(options || {})
    json['id'] = id.to_s
    json['sent_as_role'] = sent_as_role
    json
  end
end