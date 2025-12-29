# app/models/learner.rb
class Learner
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # ======================== LEGACY FIELDS ========================
  field :firstName,        as: :first_name, type: String
  field :lastName,         as: :last_name, type: String
  field :accessionNumber,  as: :accession_number, type: String
  field :gender,           type: String  # Changed from Integer to String
  field :status,           type: String, default: 'active'  # Changed from Integer to String
  field :phone,            type: String
  field :telEmergency,     as: :tel_emergency, type: String
  field :telHome,          as: :tel_home, type: String
  field :whatsapp,         type: String
  field :telegram,         type: String

  # ======================== GRADE FIELD WITH ALIAS ========================
  field :gradeId, type: String
  alias_attribute :grade_id, :gradeId

  # ======================== NEW MOBILE FIELDS ========================
  field :date_of_birth,   type: Date
  field :parent_info,     type: Hash, default: {}
  field :parent_ids,      type: Array, default: []
  field :parent_auth0_ids, type: Array, default: []
  field :enrollment_date, type: Date
  field :mobile_sync_id,  type: String
  field :last_sync_at,    type: DateTime
  
  # ======================== CRITICAL FIX ========================
  # Changed from BSON::ObjectId to String to match actual data
  field :school_id, type: String, overwrite: true

  # ======================== AUTH0 FIELDS ========================
  field :auth0Id, type: String
  field :userAuth0Id, type: String

  # ======================== ADDITIONAL FIELDS ========================
  field :schoolName, type: String
  field :schoolEmail, type: String
  field :userEmail, type: String
  field :province, type: String

  # ===================== VALIDATIONS ======================
  validates :first_name, :last_name, presence: true
  validates :accession_number, presence: true, uniqueness: { scope: :school_id }

  # Gender and status are now strings
  GENDERS  = %w[M F male female other].freeze
  STATUSES = %w[active inactive graduated].freeze

  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  # ===================== ASSOCIATIONS =====================
  belongs_to :school,     class_name: 'School', optional: true
  belongs_to :created_by, class_name: 'User',   optional: true
  belongs_to :grade,      class_name: 'Grade',  optional: true

  # ======================== INDEXES ========================
  index({ school_id: 1, accessionNumber: 1 }, unique: true, sparse: true)
  index({ firstName: 1, lastName: 1 })
  index({ school_id: 1 })
  index({ mobile_sync_id: 1 }, { unique: true, sparse: true })
  index({ school_id: 1, last_sync_at: 1 })
  index({ gradeId: 1 })
  index({ parent_ids: 1 })
  index({ parent_auth0_ids: 1 })
  index({ auth0Id: 1 })
  index({ userAuth0Id: 1 })

  # ======================= CALLBACKS =======================
  before_validation :sanitize_phone_numbers

  # ========================= SCOPES =========================
  scope :active, -> { where(status: 'active') }
  scope :inactive, -> { where(status: 'inactive') }
  scope :graduated, -> { where(status: 'graduated') }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_grade, ->(grade_id) { where(gradeId: grade_id) }

  # ======================== METHODS =========================

  # Gender helpers
  def male?
    %w[M male].include?(gender)
  end

  def female?
    %w[F female].include?(gender)
  end

  def other_gender?
    gender == 'other'
  end

  def gender_text
    case gender
    when 'M', 'male' then 'Male'
    when 'F', 'female' then 'Female'
    when 'other' then 'Other'
    else 'Unknown'
    end
  end

  # Status helpers
  def active?
    status == 'active'
  end

  def inactive?
    status == 'inactive'
  end

  def graduated?
    status == 'graduated'
  end

  def status_text
    status&.capitalize || 'Unknown'
  end

  # Concatenate full name
  def full_name
    "#{first_name} #{last_name}".strip
  end

  # Associate Learner to a School by ID string (safely)
  def add_school(school_id_string)
    Rails.logger.debug "🏫 Learner#add_school: Attempting to add school with ID '#{school_id_string}' to learner #{id}"

    return false if school_id_string.blank?

    school_to_add = School.find_by(_id: school_id_string)

    unless school_to_add
      Rails.logger.warn "⚠️ Learner#add_school: School with ID '#{school_id_string}' not found."
      errors.add(:school, 'School not found.')
      return false
    end

    self.school = school_to_add

    if save
      Rails.logger.info "✅ Learner#add_school: Associated school '#{school_name}' with learner #{full_name}."
      true
    else
      Rails.logger.error "❌ Learner#add_school: Failed to save learner. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # Helper for school name for API or UI
  def school_name
    schoolName || school&.schoolName || school&.name
  end

  # Helper for grade name for API or UI
  def grade_name
    grade&.name
  end

  # Returns primary contact number in priority order
  def primary_contact
    phone.presence || whatsapp.presence || tel_home.presence
  end

  # Returns emergency contact or falls back to primary contact
  def emergency_contact
    tel_emergency.presence || primary_contact
  end

  # Serialize to API hash
  def to_api_hash
    {
      id: id.to_s,
      first_name: first_name,
      last_name: last_name,
      full_name: full_name,
      accession_number: accession_number,
      gender: gender,
      gender_text: gender_text,
      status: status,
      status_text: status_text,
      school_id: school_id&.to_s,
      school_name: school_name,
      school_email: schoolEmail,
      grade_id: grade_id&.to_s,
      grade_name: grade_name,
      contact: {
        phone: phone,
        whatsapp: whatsapp,
        tel_home: tel_home,
        tel_emergency: tel_emergency,
        telegram: telegram
      },
      date_of_birth: date_of_birth,
      parent_info: parent_info,
      enrollment_date: enrollment_date,
      mobile_sync_id: mobile_sync_id,
      last_sync_at: last_sync_at,
      parent_auth0_ids: parent_auth0_ids,
      auth0_id: auth0Id,
      user_auth0_id: userAuth0Id,
      user_email: userEmail,
      province: province,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  # Add parent auth0_id to learner
  def add_parent(auth0_id)
    return false if auth0_id.blank?
    
    if parent_auth0_ids.exclude?(auth0_id)
      self.parent_auth0_ids = parent_auth0_ids + [auth0_id]
      save
    else
      true
    end
  end

  # Remove parent auth0_id from learner
  def remove_parent(auth0_id)
    return false if auth0_id.blank?
    
    if parent_auth0_ids.include?(auth0_id)
      self.parent_auth0_ids = parent_auth0_ids - [auth0_id]
      save
    else
      true
    end
  end

  # Get all parents as User objects
  def parents
    return [] if parent_auth0_ids.blank?
    User.where(:auth0_id.in => parent_auth0_ids)
  end

  # Check if user is a parent of this learner
  def parent?(user)
    user && parent_auth0_ids.include?(user.auth0_id)
  end

  private

  # Sanitize phone number fields removing unwanted characters
  def sanitize_phone_numbers
    %w[phone tel_emergency tel_home whatsapp telegram].each do |field|
      value = send(field)
      next unless value.present?

      sanitized = value.gsub(/[^\d\+\-\(\)\s]/, '')
      send("#{field}=", sanitized.strip)
    end
  end
end