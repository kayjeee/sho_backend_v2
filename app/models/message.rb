# frozen_string_literal: true

class Message
  include Mongoid::Document
  include Mongoid::Timestamps

  # =========================================================
  # FIELDS
  # =========================================================
  field :content,     type: String

  field :sender_id,   type: String
  field :user_id,     type: String
  field :receiver_id, type: String

  field :school_id,   type: String
  field :schoolName,  type: String
  field :name,        type: String

  field :read,        type: Boolean, default: false
  field :reactions,   type: Array,   default: []
  field :is_pinned,   type: Boolean, default: false
  field :starred_by,  type: Array,   default: []

  field :status,      type: String, default: "sent"

  # =========================================================
  # THREADING
  # =========================================================
  field :reply_to_id,      type: BSON::ObjectId
  field :reply_to_preview, type: String

  # =========================================================
  # ATTACHMENTS
  # =========================================================
  field :attachment_url,  type: String
  field :attachment_type, type: String
  field :attachment_name, type: String
  field :attachment_size, type: Integer

  # =========================================================
  # CONSTANTS
  # =========================================================
  STATUSES = %w[sent delivered read].freeze

  ATTACHMENT_TYPES = %w[
    image
    pdf
    video
    audio
    other
  ].freeze

  # =========================================================
  # INDEXES
  # =========================================================
  index({ conversation_id: 1, created_at: 1 })
  index({ sender_id: 1 })
  index({ receiver_id: 1 })
  index({ school_id: 1 })
  index({ conversation_id: 1, is_pinned: 1 })
  index({ starred_by: 1 })
  index({ content: "text" })

  # =========================================================
  # ASSOCIATIONS
  # =========================================================
  belongs_to :school,
             class_name: "School",
             inverse_of: :messages,
             optional:   true

  belongs_to :conversation,
             class_name: "Conversation",
             inverse_of: :messages

  belongs_to :sender,
             class_name: "User",
             inverse_of: :sent_messages,
             optional:   true

  belongs_to :receiver,
             class_name: "User",
             inverse_of: :received_messages,
             optional:   true

  belongs_to :parent_message,
             class_name:  "Message",
             foreign_key: :reply_to_id,
             optional:    true

  # =========================================================
  # VALIDATIONS
  # =========================================================
  validates :content,
            presence: true,
            unless: -> { attachment_url.present? }

  validates :sender_id,    presence: true
  validates :conversation, presence: true

  validates :status,
            inclusion: { in: STATUSES }

  validates :attachment_type,
            inclusion: {
              in:      ATTACHMENT_TYPES,
              message: "%{value} is not a valid attachment type"
            },
            allow_blank: true

  # =========================================================
  # CALLBACKS
  # =========================================================
  before_validation :normalize_content
  before_validation :normalize_attachment_type
  before_create     :populate_reply_preview

  # Mongoid 9.0.x has a bug in after_create_commit — the internal
  # set_options_for_callbacks! method only accepts 1 argument but the
  # callback registration passes 2, crashing at class load time.
  #
  # Workaround: use after_create for both broadcast and notification.
  # The notification job is enqueued with perform_later which runs
  # asynchronously, so it's effectively post-commit safe.
  after_create :broadcast_update!
  after_create :enqueue_notification

  # =========================================================
  # THREADING
  # =========================================================
  def populate_reply_preview
    return if reply_to_id.blank?

    parent = Message.find(reply_to_id) rescue nil
    return unless parent

    if parent.content.present?
      self.reply_to_preview = parent.content.truncate(80)
    elsif parent.attachment_url.present?
      self.reply_to_preview = "Attachment"
    end
  end

  # =========================================================
  # NORMALIZATION
  # =========================================================

  # Normalizes blank/empty content to nil so the presence validator
  # correctly skips when attachment_url is present.
  # "" is blank in Ruby but NOT nil — presence: true fires on "".
  def normalize_content
    self.content = nil if content.blank?
  end

  def normalize_attachment_type
    return if attachment_type.blank?

    base = attachment_type.to_s.split(";").first.strip

    # "audio/webm;codecs=opus" → "audio"
    # "image/jpeg"             → "image"
    # "audio"                  → "audio" (already clean)
    self.attachment_type =
      base.include?("/") ? base.split("/").first : base
  end

  # =========================================================
  # REACTIONS
  # =========================================================
  def toggle_reaction!(emoji, user_id)
    emoji   = emoji.to_s
    user_id = user_id.to_s

    raise ArgumentError, "emoji is required"   if emoji.blank?
    raise ArgumentError, "user_id is required" if user_id.blank?

    removed = self.class.collection.find(
      _id: id,
      "reactions.emoji"    => emoji,
      "reactions.user_ids" => user_id
    ).find_one_and_update(
      { "$pull" => { "reactions.$.user_ids" => user_id } },
      return_document: :after
    )

    if removed
      self.class.collection.find(_id: id).find_one_and_update(
        { "$pull" => { reactions: { emoji: emoji, user_ids: [] } } },
        return_document: :after
      )
    else
      added = self.class.collection.find(
        _id: id,
        "reactions.emoji" => emoji
      ).find_one_and_update(
        { "$addToSet" => { "reactions.$.user_ids" => user_id } },
        return_document: :after
      )

      unless added
        self.class.collection.find(_id: id).find_one_and_update(
          {
            "$addToSet" => {
              reactions: { emoji: emoji, user_ids: [user_id] }
            }
          },
          return_document: :after
        )
      end
    end

    reload.tap(&:broadcast_update!)
  end

  # =========================================================
  # PINNING / STARRING
  # =========================================================
  def toggle_pin!
    update!(is_pinned: !is_pinned)
    broadcast_update!
    self
  end

  def toggle_star!(user_id)
    user_id = normalize_starred_user_id(user_id)

    raise ArgumentError, "user_id is required" if user_id.blank?

    if Array(starred_by).include?(user_id)
      self.class.collection.find(_id: id).find_one_and_update(
        { "$pull" => { starred_by: user_id } },
        return_document: :after
      )
    else
      self.class.collection.find(_id: id).find_one_and_update(
        { "$addToSet" => { starred_by: user_id } },
        return_document: :after
      )
    end

    reload
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
  # NOTIFICATIONS
  # =========================================================
  def enqueue_notification
    SendMessageNotificationJob.perform_later(id.to_s)
  end

  # =========================================================
  # DELIVERY STATUS
  # =========================================================
  def self.mark_as_delivered!(conversation, current_user)
    to_update = conversation.messages.where(
      :sender_id.ne => current_user.id.to_s,
      status:         "sent"
    )

    ids = to_update.pluck(:id)
    return 0 if ids.empty?

    to_update.update_all(status: "delivered")
    Message.in(id: ids).each(&:broadcast_update!)
    ids.size
  end

  # =========================================================
  # READ STATUS
  # =========================================================
  def self.mark_as_read!(conversation, current_user)
    to_update = conversation.messages
                            .where(:sender_id.ne => current_user.id.to_s)
                            .any_of(
                              { read: false },
                              { :status.ne => "read" }
                            )

    ids = to_update.pluck(:id)
    return 0 if ids.empty?

    to_update.update_all(read: true, status: "read")
    Message.in(id: ids).each(&:broadcast_update!)
    ids.size
  end

  private

  def normalize_starred_user_id(user_id)
    return user_id if user_id.is_a?(BSON::ObjectId)

    BSON::ObjectId.from_string(user_id.to_s)
  rescue BSON::Error::InvalidObjectId
    nil
  end
end
