# frozen_string_literal: true

class Conversation
  include Mongoid::Document
  include Mongoid::Timestamps

  # =========================================================
  # FIELDS
  # =========================================================

  # Array of participant user IDs stored as STRINGS
  field :participant_ids, type: Array, default: []

  # Cached participant lookup key
  # Example: "123,456"
  field :participants_key, type: String

  # Used for sorting latest conversations
  field :last_message_at, type: Time

  # Optional title/group name
  field :title,      type: String
  field :group_name, type: String

  # ObjectId references
  field :school_id, type: BSON::ObjectId
  field :user_id,   type: BSON::ObjectId

  # =========================================================
  # ASSOCIATIONS
  # =========================================================

  belongs_to :user,
             class_name: "User",
             inverse_of: :conversations,
             optional: true

  belongs_to :school,
             class_name: "School",
             inverse_of: :conversations,
             optional: true

  has_many :messages,
           class_name: "Message",
           inverse_of: :conversation,
           dependent: :destroy

  # =========================================================
  # VALIDATIONS
  # =========================================================

  validates :participant_ids, presence: true
  validates :school_id, presence: true

  validate :participant_ids_are_strings
  validate :must_have_at_least_one_participant

  # =========================================================
  # CALLBACKS
  # =========================================================

  before_validation :normalize_participant_ids
  before_save :generate_participants_key

  # =========================================================
  # INDEXES
  # =========================================================

  index(
    {
      participant_ids: 1,
      last_message_at: -1
    }
  )

  index(
    {
      school_id: 1,
      last_message_at: -1
    }
  )

  index({ user_id: 1 })

  index(
    {
      participants_key: 1,
      school_id: 1,
      group_name: 1
    },
    {
      sparse: true,
      name: "unique_participants_per_school"
    }
  )

  # =========================================================
  # SCOPES
  # =========================================================

  scope :for_user, lambda { |user_id|
    user_id = user_id.to_s

    Rails.logger.info(
      "[Conversation.for_user] user_id=#{user_id}"
    )

    bson_user_id = safe_object_id(user_id)

    any_of(
      { user_id: bson_user_id },
      { participant_ids: user_id }
    ).order(
      last_message_at: :desc,
      updated_at: :desc
    )
  }

  # =========================================================
  # INSTANCE METHODS
  # =========================================================

  def touch_last_message_at!
    Rails.logger.info(
      "[Conversation##{id}] touch_last_message_at!"
    )

    update_attribute(:last_message_at, Time.current)
  end

  def other_participant_ids(current_user_id)
    participant_ids.reject do |id|
      id.to_s == current_user_id.to_s
    end
  end

  def self_conversation?
    participant_ids.uniq.size == 1
  end

  def group?
    group_name.present? || participant_ids.size > 2
  end

  # =========================================================
  # DEBUG HELPERS
  # =========================================================

  def debug_summary
    {
      id: id.to_s,
      participant_ids: participant_ids,
      participants_key: participants_key,
      user_id: user_id.to_s,
      school_id: school_id.to_s,
      group_name: group_name,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  # =========================================================
  # CLASS HELPERS
  # =========================================================

  def self.safe_object_id(value)
    return value if value.is_a?(BSON::ObjectId)

    BSON::ObjectId.from_string(value.to_s)
  rescue BSON::Error::InvalidObjectId
    nil
  end

  # Safe conversation lookup for controllers
  def self.safe_find_for_user!(conversation_id, current_user)
    Rails.logger.info(
      "[Conversation.safe_find_for_user!] " \
      "conversation_id=#{conversation_id} " \
      "current_user_id=#{current_user.id}"
    )

    conversation = any_of(
      { user_id: current_user.id },
      { participant_ids: current_user.id.to_s }
    ).find_by(id: conversation_id)

    if conversation.present?
      Rails.logger.info(
        "[Conversation.safe_find_for_user!] FOUND #{conversation.id}"
      )

      Rails.logger.info(
        "[Conversation.safe_find_for_user!] DATA=#{conversation.debug_summary}"
      )
    else
      Rails.logger.warn(
        "[Conversation.safe_find_for_user!] Conversation NOT FOUND"
      )
    end

    conversation
  rescue Mongoid::Errors::DocumentNotFound => e
    Rails.logger.error(
      "[Conversation.safe_find_for_user!] DocumentNotFound #{e.message}"
    )

    nil
  rescue Mongoid::Errors::InvalidFind => e
    Rails.logger.error(
      "[Conversation.safe_find_for_user!] InvalidFind #{e.message}"
    )

    nil
  rescue BSON::Error::InvalidObjectId => e
    Rails.logger.error(
      "[Conversation.safe_find_for_user!] InvalidObjectId #{e.message}"
    )

    nil
  rescue StandardError => e
    Rails.logger.error(
      "[Conversation.safe_find_for_user!] #{e.class} #{e.message}"
    )

    Rails.logger.error(e.backtrace.join("\n"))

    nil
  end

  # =========================================================
  # PRIVATE
  # =========================================================

  private

  # =========================================================
  # NORMALIZATION
  # =========================================================

  def normalize_participant_ids
    Rails.logger.info(
      "[Conversation##{id || 'new'}] " \
      "Raw participant_ids=#{participant_ids.inspect}"
    )

    self.participant_ids =
      Array(participant_ids)
        .flatten
        .map(&:to_s)
        .map(&:strip)
        .reject(&:blank?)
        .uniq
        .sort

    Rails.logger.info(
      "[Conversation##{id || 'new'}] " \
      "Normalized participant_ids=#{participant_ids.inspect}"
    )
  end

  def generate_participants_key
    self.participants_key = participant_ids.join(",")

    Rails.logger.info(
      "[Conversation##{id || 'new'}] " \
      "participants_key=#{participants_key}"
    )
  end

  # =========================================================
  # VALIDATION HELPERS
  # =========================================================

  def participant_ids_are_strings
    return if participant_ids.blank?

    invalid = participant_ids.reject do |id|
      id.is_a?(String)
    end

    return if invalid.empty?

    Rails.logger.warn(
      "[Conversation Validation] " \
      "Invalid participant_ids=#{invalid.inspect}"
    )

    errors.add(
      :participant_ids,
      "must contain only string IDs"
    )
  end

  def must_have_at_least_one_participant
    return if participant_ids.present?

    Rails.logger.warn(
      "[Conversation Validation] participant_ids missing"
    )

    errors.add(
      :participant_ids,
      "must have at least one participant"
    )
  end
end