# app/models/learner.rb
class Learner
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== SNAPSHOT FIELDS ========================
  # PHYSICAL DB FIELD Naming Alignment
  # The database collection uses camelCase keys (firstName, lastName, etc.)
  # We use 'as: :ruby_name' to provide standard snake_case accessors while
  # preserving the physical field name.

  field :firstName,       as: :first_name, type: String
  field :lastName,        as: :last_name, type: String
  field :gender,          type: Integer, default: 0
  field :accessionNumber, as: :accession_number, type: String
  field :schoolName,      as: :school_name_denormalized, type: String
  field :schoolEmail,     type: String
  field :userEmail,       type: String
  field :province,        type: String
  field :auth0Id,         type: String
  field :userAuth0Id,     type: String
  field :gradeId,         as: :grade_id, type: String
  field :school_id,       type: String
  field :status,          type: Integer, default: 0

  field :phone,            type: String
  field :telEmergency,     as: :tel_emergency, type: String
  field :telHome,          as: :tel_home, type: String
  field :whatsapp,         type: String
  field :telegram,         type: String

  field :school_class_id, type: String
  field :parent_ids,      type: Array, default: []

  # ======================== NEW MOBILE FIELDS ========================
  field :date_of_birth,   type: Date
  field :parent_info,     type: Hash, default: {}
  field :enrollment_date, type: Date
  field :mobile_sync_id,  type: String
  field :last_sync_at,    type: DateTime

  # ===================== VALIDATIONS ======================
  validates :first_name, :last_name, presence: true
  validates :accession_number, uniqueness: { scope: :school_id }, allow_blank: true

  GENDERS  = { 'male' => 0, 'female' => 1, 'other' => 2 }.freeze
  STATUSES = { 'active' => 0, 'inactive' => 1, 'graduated' => 2 }.freeze

  validates :gender, inclusion: { in: GENDERS.values }, allow_nil: true
  validates :status, inclusion: { in: STATUSES.values }, allow_nil: true

  # ===================== ASSOCIATIONS =====================
  # Use explicit foreign keys to match the physical database field 'gradeId'
  belongs_to :school,     class_name: 'School', foreign_key: :school_id, optional: true
  belongs_to :created_by, class_name: 'User',   optional: true
  belongs_to :grade,      class_name: 'Grade',  foreign_key: :gradeId,   optional: true
  belongs_to :school_class, class_name: 'SchoolClass', inverse_of: :learners, optional: true

  # ======================== INDEXES ========================
  index({ school_id: 1, accession_number: 1 }, unique: true, sparse: true)
  index({ firstName: 1, lastName: 1 })
  index({ school_id: 1 })
  index({ mobile_sync_id: 1 }, { unique: true, sparse: true })
  index({ school_id: 1, last_sync_at: 1 })
  index({ gradeId: 1 })

  # ======================= CALLBACKS =======================
  before_validation :set_default_accession_number, if: -> { accession_number.blank? }
  before_validation :sanitize_phone_numbers

  # ========================= SCOPES =========================
  scope :active,    -> { where(status: STATUSES['active']) }
  scope :inactive,  -> { where(status: STATUSES['inactive']) }
  scope :graduated, -> { where(status: STATUSES['graduated']) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_grade,  ->(grade_id)  { where(grade_id: grade_id) }

  # ======================== METHODS =========================

  # Gender helpers
  def male?         = gender == GENDERS['male']
  def female?       = gender == GENDERS['female']
  def other_gender? = gender == GENDERS['other']

  def gender_text
    GENDERS.key(gender)&.capitalize || 'Unknown'
  end

  # Status helpers
  def active?    = status == STATUSES['active']
  def inactive?  = status == STATUSES['inactive']
  def graduated? = status == STATUSES['graduated']

  def status_text
    STATUSES.key(status)&.capitalize || 'Unknown'
  end

  def parents
    User.where(:id.in => parent_ids, roles: "parent")
  end

  def add_parent(parent_or_id)
    parent_id = if parent_or_id.is_a?(User)
                  parent_or_id.id
                elsif BSON::ObjectId.legal?(parent_or_id)
                  BSON::ObjectId.from_string(parent_or_id.to_s)
                else
                  user = User.find_by(auth0_id: parent_or_id)
                  user&.id
                end

    return false if parent_id.blank?

    self.parent_ids ||= []
    unless self.parent_ids.include?(parent_id)
      new_parent_ids = self.parent_ids.dup
      new_parent_ids << parent_id
      self.parent_ids = new_parent_ids
    end
    save
  end

  # Concatenate full name
  def full_name
    "#{first_name} #{last_name}".strip
  end

  # Associate Learner to a School by ID string (safely)
  def add_school(school_id_string)
    Rails.logger.debug "🏫 Learner#add_school: Attempting to add school with ID '#{school_id_string}' to learner #{id}"

    return false if school_id_string.blank?

    self.school_id = school_id_string

    school_bson_id = parse_bson_id(school_id_string)
    if school_bson_id
      school_to_add = School.find_by(_id: school_bson_id)
      self.school = school_to_add if school_to_add
    end

    if save
      Rails.logger.info "✅ Learner#add_school: Associated school ID '#{school_id}' with learner #{full_name}."
      true
    else
      Rails.logger.error "❌ Learner#add_school: Failed to save learner. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  # Helper for school name for API or UI
  def school_name
    school&.schoolName || school&.name || school_name_denormalized
  end

  # Force-sets the learner's grade ID in the raw MongoDB collection to bypass Mongoid association casting/no-op issues
  def force_grade_id!(new_grade_id)
    return if new_grade_id.blank?

    # Update the document in MongoDB collection directly to guarantee write
    Learner.collection.find(_id: id).update_one(
      { "$set" => { "gradeId" => new_grade_id.to_s } }
    )

    # Reload the document/Mongoid fields to keep instance in-sync
    reload
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

  def accession_number
    read_attribute(:accessionNumber) || read_attribute(:accession_number) || self[:accessionNumber] || self[:accession_number]
  end

  def accessionNumber
    accession_number
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
      school_id: school_id.to_s,
      school_name: school_name,
      grade_id: grade_id.to_s,
      grade_name: grade_name,
      auth0Id: auth0Id,
      userAuth0Id: userAuth0Id,
      userEmail: userEmail,
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
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  # Generates a default accession number if missing
  def set_default_accession_number
    timestamp     = Time.now.to_i.to_s.last(6)
    random_suffix = rand(100..999)
    school_prefix = school_name&.first(3)&.upcase || 'STD'

    self.accession_number = "#{school_prefix}#{timestamp}#{random_suffix}"
  end

  # Sanitize phone number fields removing unwanted characters
  def sanitize_phone_numbers
    %w[phone tel_emergency tel_home whatsapp telegram].each do |field|
      value = send(field)
      next unless value.present?

      sanitized = value.gsub(/[^\d\+\-\(\)\s]/, '')
      send("#{field}=", sanitized.strip)
    end
  end

  # Safely parse BSON ObjectId from string or BSON::ObjectId
  def parse_bson_id(id_string)
    case id_string
    when BSON::ObjectId
      id_string
    when String
      BSON::ObjectId.from_string(id_string.strip)
    else
      BSON::ObjectId.from_string(id_string.to_s.strip)
    end
  rescue BSON::ObjectId::Invalid => e
    Rails.logger.error "❌ Learner#parse_bson_id: Invalid BSON ID '#{id_string}'. Error: #{e.message}"
    errors.add(:school, 'Invalid school ID format.')
    nil
  end
end
