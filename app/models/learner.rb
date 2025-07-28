# app/models/learner.rb
class Learner
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :first_name,        type: String
  field :last_name,         type: String
  field :accession_number,  type: String
  field :gender,            type: Integer, default: 0
  field :status,            type: Integer, default: 0
  field :phone,             type: String
  field :tel_emergency,     type: String
  field :tel_home,          type: String
  field :whatsapp,          type: String
  field :telegram,          type: String

  # ===================== VALIDATIONS ======================
  validates :first_name, :last_name, presence: true
  validates :accession_number, uniqueness: { scope: :school_id }, allow_blank: true

  # Constants for gender and status
  GENDERS = { 'male' => 0, 'female' => 1, 'other' => 2 }.freeze
  STATUSES = { 'active' => 0, 'inactive' => 1, 'graduated' => 2 }.freeze

  validates :gender, inclusion: { in: GENDERS.values }
  validates :status, inclusion: { in: STATUSES.values }

  # ===================== ASSOCIATIONS =====================
  # References to other documents using BSON::ObjectId
  belongs_to :school, class_name: 'School', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :grade, class_name: 'Grade', optional: true

  # ======================== INDEXES =======================
  index({ school_id: 1, accession_number: 1 }, { unique: true, sparse: true })
  index({ first_name: 1, last_name: 1 })
  index({ school_id: 1 })

  # ======================== CALLBACKS =======================
  before_validation :set_default_accession_number, if: -> { accession_number.blank? }
  before_validation :sanitize_phone_numbers

  # ========================= SCOPES ========================
  scope :active, -> { where(status: 0) }
  scope :inactive, -> { where(status: 1) }
  scope :graduated, -> { where(status: 2) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_grade, ->(grade_id) { where(grade_id: grade_id) }

  # ========================= METHODS ========================

  # Helper methods for gender
  def male?
    gender == 0
  end

  def female?
    gender == 1
  end

  def other_gender?
    gender == 2
  end

  def gender_text
    case gender
    when 0 then 'Male'
    when 1 then 'Female'
    when 2 then 'Other'
    else 'Unknown'
    end
  end

  # Helper methods for status
  def active?
    status == 0
  end

  def inactive?
    status == 1
  end

  def graduated?
    status == 2
  end

  def status_text
    case status
    when 0 then 'Active'
    when 1 then 'Inactive'
    when 2 then 'Graduated'
    else 'Unknown'
    end
  end

  # Full name helper
  def full_name
    "#{first_name} #{last_name}".strip
  end

  # Add a school to the learner (similar to User model pattern)
  def add_school(school_id_string)
    Rails.logger.debug "🏫 Learner#add_school: Attempting to add school with ID string '#{school_id_string}' to learner #{id}"

    return false if school_id_string.blank?

    begin
      # Handle both string IDs and BSON::ObjectId objects
      school_bson_id = case school_id_string
                      when BSON::ObjectId
                        school_id_string
                      when String
                        BSON::ObjectId.from_string(school_id_string.strip)
                      else
                        BSON::ObjectId.from_string(school_id_string.to_s.strip)
                      end
    rescue BSON::ObjectId::Invalid => e
      Rails.logger.error "❌ Learner#add_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'. Error: #{e.message}"
      errors.add(:school, "Invalid school ID format.")
      return false
    end

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ Learner#add_school: School with ID '#{school_id_string}' not found in database."
      errors.add(:school, "School not found.")
      return false
    end

    self.school = school_to_add

    if save
      Rails.logger.info "✅ Learner#add_school: Successfully associated school '#{school_to_add.schoolName || school_to_add.name}' with learner #{full_name}."
      true
    else
      Rails.logger.error "❌ Learner#add_school: Failed to save learner #{id} after associating school. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # Get school name (handles both schoolName and name fields)
  def school_name
    school&.schoolName || school&.name
  end

  # Get grade name
  def grade_name
    grade&.name
  end

  # Contact information methods
  def primary_contact
    phone.presence || whatsapp.presence || tel_home.presence
  end

  def emergency_contact
    tel_emergency.presence || primary_contact
  end

  # Export to hash for API responses
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
      grade_id: grade_id&.to_s,
      grade_name: grade_name,
      contact: {
        phone: phone,
        whatsapp: whatsapp,
        tel_home: tel_home,
        tel_emergency: tel_emergency,
        telegram: telegram
      },
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def set_default_accession_number
    # Generate a more unique accession number
    timestamp = Time.now.to_i.to_s.last(6)
    random_suffix = rand(100..999)
    school_prefix = school_name&.first(3)&.upcase || 'STD'
    
    self.accession_number = "#{school_prefix}#{timestamp}#{random_suffix}"
  end

  def sanitize_phone_numbers
    # Remove any non-digit characters from phone numbers
    %w[phone tel_emergency tel_home whatsapp telegram].each do |field|
      value = send(field)
      if value.present?
        # Keep only digits, +, -, (, ), and spaces
        sanitized = value.gsub(/[^\d\+\-\(\)\s]/, '')
        send("#{field}=", sanitized.strip)
      end
    end
  end
end