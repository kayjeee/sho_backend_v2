class Conversation
    include Mongoid::Document
    include Mongoid::Timestamps

    field :school_id, type: BSON::ObjectId
    field :user_id, type: BSON::ObjectId

    belongs_to :user, class_name: "User", inverse_of: :conversations
    belongs_to :school, class_name: "School", inverse_of: :conversations, optional: true

    has_many :messages, class_name: "Message", inverse_of: :conversation

    def self.find_or_create_by_school_and_user(school_id, user_id)
      conversation = find_by(school_id: school_id, user_id: user_id)
      conversation || create(school_id: school_id, user_id: user_id)
    end
end
