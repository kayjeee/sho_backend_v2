class Conversation
  include Mongoid::Document
  include Mongoid::Timestamps

  field :school_id,       type: BSON::ObjectId
  field :user_id,         type: BSON::ObjectId

  # ======================== GROUP CONVERSATION FIELDS ========================
  field :scope_type,      type: String, default: 'individual'
  field :scope_id,        type: String
  field :participant_ids, type: Array,  default: []
  field :academic_year,   type: String
  field :term_id,         type: String
  field :title,           type: String

  SCOPE_TYPES = %w[individual class grade school teachers self].freeze

  # ===================== VALIDATIONS ======================
  validates :scope_type, inclusion: { in: SCOPE_TYPES }

  # ===================== ASSOCIATIONS =====================
  belongs_to :user, class_name: 'User', inverse_of: :conversations, optional: true
  belongs_to :school, class_name: 'School', inverse_of: :conversations, optional: true

  has_many :messages, class_name: 'Message', inverse_of: :conversation, dependent: :destroy

  # ======================== INDEXES =======================
  index({ scope_type: 1, scope_id: 1 })
  index({ participant_ids: 1 })
  index({ school_id: 1, academic_year: 1, term_id: 1 })

  # ========================= SCOPES ========================
  scope :individual_conversations, -> { where(scope_type: 'individual') }
  scope :group_conversations,      -> { where(:scope_type.ne => 'individual') }
  scope :by_scope_type,            ->(type) { where(scope_type: type.to_s) }
  scope :by_scope_id,              ->(sid)  { where(scope_id: sid.to_s) }
  scope :by_academic_year,         ->(year) { where(academic_year: year.to_s) }
  scope :by_term_id,               ->(tid)  { where(term_id: tid.to_s) }

  # ========================= METHODS ========================
  def self.find_or_create_by_school_and_user(school_id, user_id)
    s_bson = BSON::ObjectId.legal?(school_id.to_s) ? BSON::ObjectId.from_string(school_id.to_s) : school_id
    u_bson = BSON::ObjectId.legal?(user_id.to_s) ? BSON::ObjectId.from_string(user_id.to_s) : user_id

    conversation = where(school_id: s_bson, user_id: u_bson, scope_type: 'individual').first
    conversation || create(school_id: s_bson, user_id: u_bson, scope_type: 'individual', participant_ids: [u_bson.to_s])
  end

  def resolved_participant_ids
    if scope_type == 'individual'
      p_ids = Array(participant_ids).map(&:to_s).reject(&:blank?)
      return p_ids if p_ids.present?
      return [user_id.to_s].compact
    end

    Array(participant_ids).map(&:to_s).reject(&:blank?)
  end

  def participant?(user_or_id)
    uid_str = if user_or_id.is_a?(User)
                user_or_id.id.to_s
              elsif user_or_id.respond_to?(:auth0_id) && user_or_id.auth0_id.present?
                user_or_id.id.to_s
              else
                user_or_id.to_s
              end

    return true if scope_type == 'individual' && user_id.to_s == uid_str
    resolved_participant_ids.include?(uid_str)
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id&.to_s,
      user_id: user_id&.to_s,
      scope_type: scope_type,
      scope_id: scope_id,
      participant_ids: resolved_participant_ids,
      academic_year: academic_year,
      term_id: term_id,
      title: title,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
end
