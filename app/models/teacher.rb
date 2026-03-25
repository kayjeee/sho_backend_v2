# app/models/teacher.rb
class Teacher
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,             type: String
  field :email,            type: String
  field :auth0_id,         type: String
  field :phone,            type: String
  field :recipient_phone_number, type: String
  field :slug,             type: String
  field :status,           type: String, default: 'active'
  field :bio,              type: String
  field :avatar,           type: String
  field :subjects,         type: Array,  default: []

  # ===================== ASSOCIATIONS =====================
  belongs_to :school
  belongs_to :user, inverse_of: :teacher_profile, optional: true
  has_many :teacher_grade_assignments, foreign_key: :teacher_model_id

  # ===================== VALIDATIONS ======================
  validates :name,     presence: true
  validates :auth0_id, presence: true
  validates :school_id, presence: true
  validates :slug,     presence: true, uniqueness: { scope: :school_id }

  # ======================== INDEXES =======================
  index({ auth0_id: 1 })
  index({ school_id: 1 })
  index({ slug: 1 })
  index({ auth0_id: 1, school_id: 1 }, { unique: true })

  # ======================== CALLBACKS =====================
  before_validation :generate_slug, if: :name_changed?

  def generate_slug
    return if name.blank?
    base = name.to_s.downcase.gsub(/\s+/, '-').gsub(/[^a-z0-9-]/, '')

    # Use user's last 4 chars for short_id if available, else random
    suffix = if user_id.present?
               user_id.to_s.last(4)
             elsif auth0_id.present?
               auth0_id.to_s.last(4)
             else
               SecureRandom.hex(2)
             end

    self.slug ||= "#{base}-#{suffix}"
  end

  def to_api_hash
    {
      id: id.to_s,
      name: name,
      email: email,
      auth0_id: auth0_id,
      slug: slug,
      status: status,
      school_id: school_id&.to_s,
      joinedAt: created_at&.iso8601
    }
  end
end
