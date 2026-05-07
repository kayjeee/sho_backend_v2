# frozen_string_literal: true

class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  # =========================================================
  # FIELDS
  # =========================================================
  field :content,    type: String
  field :sender_id,  type: String
  field :user_id,    type: String
  field :receiver_id, type: String

  field :school_id,  type: String
  field :schoolName, type: String
  field :name,       type: String

  field :read,       type: Boolean, default: false
  field :reactions,  type: Array,   default: []
  field :status,     type: String,  default: "sent"

  # =========================================================
  # ATTACHMENTS
  # =========================================================
  field :attachment_url,  type: String
  field :attachment_type, type: String # image/pdf/video/audio/other
  field :attachment_name, type: String
  field :attachment_size, type: Integer # bytes

  # =========================================================
  # INDEXES
  # =========================================================

  # Text search index
  index({ content: "text" }, { name: "content_text_index" })

  # Helpful query indexes
  index({ conversation_id: 1 })
  index({ sender_id: 1 })
  index({ receiver_id: 1 })
  index({ created_at: -1 })
  index({ status: 1 })

  # =========================================================
  # RELATIONSHIPS
  # =========================================================
  belongs_to :school,
             class_name: "School",
             inverse_of: :messages,
             optional: true,
             primary_key: :id,
             foreign_key: :school_id

  belongs_to :conversation,
             class_name: "Conversation",
             inverse_of: :messages

  belongs_to :sender,
             class_name: "User",
             inverse_of: :sent_messages,
             optional: true,
             primary_key: :id,
             foreign_key: :sender_id

  belongs_to :receiver,
             class_name: "User",
             inverse_of: :received_messages,
             optional: true,
             primary_key: :id,
             foreign_key: :receiver_id

  # =========================================================
  # VALIDATIONS
  # =========================================================
  validates :content,
            presence: true,
            unless: -> { attachment_url.present? }

  validates :sender_id, presence: true
  validates :conversation, presence: true

  validates :status,
            inclusion: {
              in: %w[sent delivered read]
            }

  # =========================================================
  # CALLBACKS
  # =========================================================

  # Mongoid 9 safe callback
  after_create do |doc|
    doc.broadcast_update!
  end

  # =========================================================
  # REACTIONS
  # =========================================================
  def toggle_reaction!(emoji, user_id)
    emoji = emoji.to_s
    user_id = user_id.to_s

    raise ArgumentError, "emoji is required" if emoji.blank?
    raise ArgumentError, "user_id is required" if user_id.blank?

    removed = self.class.collection.find(
      _id: id,
      "reactions.emoji" => emoji,
      "reactions.user_ids" => user_id
    ).find_one_and_update(
      {
        "$pull" => {
          "reactions.$.user_ids" => user_id
        }
      },
      return_document: :after
    )

    if removed
      self.class.collection.find(_id: id).find_one_and_update(
        {
          "$pull" => {
            reactions: {
              emoji: emoji,
              user_ids: []
            }
          }
        },
        return_document: :after
      )
    else
      added_to_existing = self.class.collection.find(
        _id: id,
        "reactions.emoji" => emoji
      ).find_one_and_update(
        {
          "$addToSet" => {
            "reactions.$.user_ids" => user_id
          }
        },
        return_document: :after
      )

      unless added_to_existing
        self.class.collection.find(_id: id).find_one_and_update(
          {
            "$addToSet" => {
              reactions: {
                emoji: emoji,
                user_ids: [user_id]
              }
            }
          },
          return_document: :after
        )
      end
    end

    reload.tap(&:broadcast_update!)
  end

  # =========================================================
  # BROADCASTING
  # =========================================================
  def broadcast_update!
    MessagesChannel.broadcast_to(
      conversation,
      MessageSerializer.new(self).as_json
    )
  end

  # =========================================================
  # DELIVERY STATUS
  # =========================================================
  def self.mark_as_delivered!(conversation, current_user)
    to_update = conversation.messages.where(
      :sender_id.ne => current_user.id.to_s,
      status: "sent"
    )

    ids = to_update.pluck(:id)
    return 0 if ids.empty?

    to_update.update_all(status: "delivered")

    # Broadcast updates
    Message.in(id: ids).each(&:broadcast_update!)

    ids.size
  end

  def self.mark_as_read!(conversation, current_user)
    to_update = conversation.messages
                            .where(:sender_id.ne => current_user.id.to_s)
                            .any_of(
                              { read: false },
                              { :status.ne => "read" }
                            )

    ids = to_update.pluck(:id)
    return 0 if ids.empty?

    to_update.update_all(
      read: true,
      status: "read"
    )

    # Broadcast updates
    Message.in(id: ids).each(&:broadcast_update!)

    ids.size
  end
end