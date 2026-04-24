# frozen_string_literal: true

class Conversation
  include Mongoid::Document
  include Mongoid::Timestamps   # provides created_at, updated_at

  # ── Fields ──────────────────────────────────────────────────────────────────

  # Sorted array of participant User ID strings.
  # Stored as strings (not ObjectIds) so the controller can compare with
  # @current_user.id.to_s without casting. Always keep sorted + unique.
  field :participant_ids,  type: Array,          default: []

  # Denormalised timestamp — set by the MessagesController every time a new
  # message is saved. Used to sort conversations newest-first without a join.
  # Falls back to updated_at in the controller if nil (legacy records).
  field :last_message_at,  type: Time

  # Optional title override (e.g. group chat name). Usually nil — the
  # controller derives the display title from participant names at runtime.
  field :title,            type: String

  # Foreign keys stored as ObjectIds (native Mongoid convention).
  field :school_id,        type: BSON::ObjectId
  field :user_id,          type: BSON::ObjectId

  # ── Associations ─────────────────────────────────────────────────────────────

  # The user who created the conversation.
  # optional: true prevents a validation error if the creator is later deleted.
  belongs_to :user,
             class_name:   'User',
             inverse_of:   :conversations,
             optional:     true

  # School context — not every conversation belongs to a school.
  belongs_to :school,
             class_name:   'School',
             inverse_of:   :conversations,
             optional:     true

  # Messages are stored in their own collection, referencing this conversation.
  # dependent: :destroy ensures no orphaned messages remain if a conversation
  # is deleted.
  has_many :messages,
           class_name:   'Message',
           inverse_of:   :conversation,
           dependent:    :destroy

  # ── Validations ──────────────────────────────────────────────────────────────

  # A conversation must have at least one participant (the creator).
  validates :participant_ids, presence: true
  validate  :participant_ids_are_strings

  # school_id is required for all new conversations created through the API.
  # Marked optional on the association above so Mongoid doesn't do a DB lookup
  # on every instantiation; we enforce the requirement here instead.
  validates :school_id, presence: true

  # ── Callbacks ────────────────────────────────────────────────────────────────

  before_save :normalise_participant_ids

  # ── Indexes ──────────────────────────────────────────────────────────────────

  # Primary access pattern: "all conversations for a user"
  # Compound with last_message_at so the sort is covered by the index.
  index({ participant_ids: 1, last_message_at: -1 })

  # Secondary access pattern: "all conversations for a school"
  index({ school_id: 1, last_message_at: -1 })

  # Lookup by creator — used in set_conversation authorisation guard.
  index({ user_id: 1 })

  # Unique-ness enforcement: prevents duplicate conversations between the same
  # set of participants in the same school.
  # sparse: true allows multiple documents where school_id is nil.
  index(
    { participant_ids: 1, school_id: 1 },
    { unique: true, sparse: true, name: 'unique_participants_per_school' }
  )

  # ── Scopes ───────────────────────────────────────────────────────────────────

  # All conversations a given user participates in, newest first.
  scope :for_user, ->(user_id) {
    any_of(
      { user_id: user_id },
      { participant_ids: user_id.to_s }
    ).order(last_message_at: :desc, updated_at: :desc)
  }

  # ── Instance helpers ─────────────────────────────────────────────────────────

  # Convenience: touch last_message_at. Called by MessagesController after save.
  def touch_last_message_at!
    update_attribute(:last_message_at, Time.current)
  end

  # Returns participant IDs excluding a given user ID.
  def other_participant_ids(current_user_id)
    participant_ids.reject { |id| id.to_s == current_user_id.to_s }
  end

  # True when the conversation has only one unique participant (self-notes).
  def self_conversation?
    participant_ids.uniq.size == 1
  end

  private

  # Ensures participant_ids is always an array of plain strings, sorted and
  # deduplicated. Prevents type mismatches when comparing against string user IDs.
  def normalise_participant_ids
    self.participant_ids = Array(participant_ids)
                             .map(&:to_s)
                             .reject(&:blank?)
                             .uniq
                             .sort
  end

  def participant_ids_are_strings
    return unless participant_ids.present?

    non_strings = participant_ids.reject { |id| id.is_a?(String) }
    return if non_strings.empty?

    errors.add(:participant_ids, "must contain only string IDs (got: #{non_strings.map(&:class).uniq.join(', ')})")
  end
end