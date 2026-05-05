class School
  include Mongoid::Document
  include Mongoid::Timestamps

  # Basic Information
  field :schoolName, type: String
  field :slug, type: String
  field :schoolEmail, type: String
  
  # Location
  field :country, type: String
  field :city, type: String
  field :province, type: String
  field :latitude, type: Float
  field :longitude, type: Float
  
  # Address
  field :line1, type: String
  field :line2, type: String
  field :postalCode, type: String
  
  # Social Media
  field :facebook, type: String
  field :linkedin, type: String
  field :tiktok, type: String
  field :website, type: String
  
  # Branding
  field :logo, type: String
  field :theme, type: String, default: ""  # Changed to String
  
  # Financial
  field :cash_account, type: Float, default: 0.0
  field :payment_history, type: Array, default: []
  
  # Users & Invitations
  field :adminUsers, type: Array, default: []
  field :invites, type: Array, default: []
  
  # Status & Metadata
  field :status, type: String, default: "active"
  field :user_id, type: String
  field :user_email, type: String
  field :school_created_by, type: String
  
  # Associations
  has_many :grades,   dependent: :destroy
  has_many :messages, inverse_of: :school
  
  # Callbacks
  before_validation :generate_slug, if: :schoolName_changed?

  # Validations
  validates :schoolName, presence: true, uniqueness: true
  validates :schoolEmail, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :country, presence: true
  
  # Indexes
  index({ schoolName: 1 }, { unique: true })
  index({ slug: 1 }, { unique: true })
  index({ schoolEmail: 1 })
  index({ status: 1 })
  index({ user_id: 1 })
  index({ created_at: -1 })
  
  # Helper method to get grades
  def grades_list
    grades.order(created_at: :desc)
  end

  # Serialization for API
  def to_api_hash(include_stats: false)
    hash = {
      id: id.to_s,
      schoolName: schoolName,
      slug: slug,
      schoolEmail: schoolEmail,
      country: country,
      city: city,
      province: province,
      line1: line1,
      line2: line2,
      postalCode: postalCode,
      logo: logo,
      theme: theme,
      status: status,
      user_id: user_id,
      user_email: user_email,
      created_at: created_at,
      updated_at: updated_at
    }

    if include_stats
      hash[:stats] = {
        teacherCount: UserSchoolRole.where(school_id: id, role: 'teacher').count,
        learnerCount: Learner.where(school_id: id).count,
        gradeCount: grades.count
      }
    end

    hash
  end

  private

  def generate_slug
    self.slug = schoolName.parameterize if schoolName.present?
  end
end
