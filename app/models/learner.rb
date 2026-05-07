# app/models/learner.rb

class Learner
  include Mongoid::Document
  include Mongoid::Timestamps

  # =========================================================
  # LEGACY FIELDS
  # =========================================================
  field :firstName,        as: :first_name, type: String
  field :lastName,         as: :last_name,  type: String
  field :accession_number, type: String

  field :gender,           type: Integer, default: 0
  field :status,           type: Integer, default: 0

  field :phone,            type: String
  field :tel_emergency,    type: String
  field :tel_home,         type: String
  field :whatsapp,         type: String
  field :telegram,         type: String

  # =========================================================
  # GRADE FIELD WITH ALIAS
  # =========================================================
  # Stored in MongoDB as gradeId (camelCase)
  # Used in Rails as grade_id (snake_case)
  field :gradeId, type: String

  alias_attribute :grade_id, :gradeId

  # =========================================================
  # MOBILE / SYNC FIELDS
  # =========================================================
  field :date_of_birth,   type: Date
  field :parent_info,     type: Hash, default: {}
  field :enrollment_date, type: Date

  field :mobile_sync_id,  type: String
  field :last_sync_at,    type: DateTime

  # =========================================================
  # CONSTANTS
  # =========================================================
  GENDERS = {
    "male"   => 0,
    "female" => 1,
    "other"  => 2
  }.freeze

  STATUSES = {
    "active"    => 0,
    "inactive"  => 1,
    "graduated" => 2
  }.freeze

  # =========================================================
  # VALIDATIONS
  # =========================================================
  validates :first_name, :last_name, presence: true

  validates :accession_number,
            uniqueness: {
              scope: :school_id
            },
            allow_blank: true

  validates :gender,
            inclusion: {
              in: GENDERS.values
            }

  validates :status,
            inclusion: {
              in: STATUSES.values
            }

  # =========================================================
  # ASSOCIATIONS
  # =========================================================
  belongs_to :school,
             class_name: "School",
             optional: true

  belongs_to :created_by,
             class_name: "User",
             optional: true

  belongs_to :grade,
             class_name: "Grade",
             optional: true

  # =========================================================
  # INDEXES
  # =========================================================

  # IMPORTANT FIX:
  # sparse: true prevents duplicate NULL errors
  # while still enforcing uniqueness for real values.
  index(
    { school_id: 1, accession_number: 1 },
    {
      unique: true,
      sparse: true
    }
  )

  index({ first_name: 1, last_name: 1 })

  index({ school_id: 1 })

  index(
    { mobile_sync_id: 1 },
    {
      unique: true,
      sparse: true
    }
  )

  index({ school_id: 1, last_sync_at: 1 })

  # Use actual MongoDB field name
  index({ gradeId: 1 })

  # =========================================================
  # CALLBACKS
  # =========================================================
  before_validation :set_default_accession_number,
                    if: -> { accession_number.blank? }

  before_validation :sanitize_phone_numbers

  # =========================================================
  # SCOPES
  # =========================================================
  scope :active,
        -> { where(status: STATUSES["active"]) }

  scope :inactive,
        -> { where(status: STATUSES["inactive"]) }

  scope :graduated,
        -> { where(status: STATUSES["graduated"]) }

  scope :by_school,
        ->(school_id) { where(school_id: school_id) }

  scope :by_grade,
        ->(grade_id) { where(gradeId: grade_id) }

  # =========================================================
  # GENDER HELPERS
  # =========================================================
  def male?
    gender == GENDERS["male"]
  end

  def female?
    gender == GENDERS["female"]
  end

  def other_gender?
    gender == GENDERS["other"]
  end

  def gender_text
    GENDERS.key(gender)&.capitalize || "Unknown"
  end

  # =========================================================
  # STATUS HELPERS
  # =========================================================
  def active?
    status == STATUSES["active"]
  end

  def inactive?
    status == STATUSES["inactive"]
  end

  def graduated?
    status == STATUSES["graduated"]
  end

  def status_text
    STATUSES.key(status)&.capitalize || "Unknown"
  end

  # =========================================================
  # NAME HELPERS
  # =========================================================
  def full_name
    "#{first_name} #{last_name}".strip
  end

  # =========================================================
  # SCHOOL HELPERS
  # =========================================================
  def add_school(school_id_string)
    Rails.logger.debug(
      "🏫 Learner#add_school: Attempting to add school with ID '#{school_id_string}' to learner #{id}"
    )

    return false if school_id_string.blank?

    school_bson_id = parse_bson_id(school_id_string)
    return false unless school_bson_id

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn(
        "⚠️ Learner#add_school: School with ID '#{school_id_string}' not found."
      )

      errors.add(:school, "School not found.")
      return false
    end

    self.school = school_to_add

    if save
      Rails.logger.info(
        "✅ Learner#add_school: Associated school '#{school_name}' with learner #{full_name}."
      )

      true
    else
      Rails.logger.error(
        "❌ Learner#add_school: Failed to save learner. Errors: #{errors.full_messages.join(', ')}"
      )

      false
    end
  end

  def school_name
    school&.schoolName || school&.name
  end

  def grade_name
    grade&.name
  end

  # =========================================================
  # CONTACT HELPERS
  # =========================================================
  def primary_contact
    phone.presence ||
      whatsapp.presence ||
      tel_home.presence
  end

  def emergency_contact
    tel_emergency.presence || primary_contact
  end

  # =========================================================
  # PARENT LINKING
  # =========================================================
  def add_parent(parent_auth0_id)
    user = User.find_by(auth0_id: parent_auth0_id)

    return false unless user

    self.parent_info ||= {}
    self.parent_info["parents"] ||= []

    self.parent_info["parents"] << {
      "user_id"   => user.id.to_s,
      "auth0_id"  => user.auth0_id,
      "name"      => user.name,
      "linked_at" => Time.current
    }

    self.parent_info["parents"].uniq! do |parent|
      parent["auth0_id"]
    end

    save
  end

  # =========================================================
  # API SERIALIZATION
  # =========================================================
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

  # =========================================================
  # AUTO GENERATE ACCESSION NUMBER
  # =========================================================
  def set_default_accession_number
    timestamp     = Time.now.to_i.to_s.last(6)
    random_suffix = rand(100..999)

    school_prefix =
      school_name&.first(3)&.upcase || "STD"

    self.accession_number =
      "#{school_prefix}#{timestamp}#{random_suffix}"
  end

  # =========================================================
  # SANITIZE PHONE NUMBERS
  # =========================================================
  def sanitize_phone_numbers
    %w[
      phone
      tel_emergency
      tel_home
      whatsapp
      telegram
    ].each do |field|

      value = send(field)

      next unless value.present?

      sanitized = value.gsub(
        /[^\d\+\-\(\)\s]/,
        ""
      )

      send("#{field}=", sanitized.strip)
    end
  end

  # =========================================================
  # SAFE BSON PARSER
  # =========================================================
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
    Rails.logger.error(
      "❌ Learner#parse_bson_id: Invalid BSON ID '#{id_string}'. Error: #{e.message}"
    )

    errors.add(:school, "Invalid school ID format.")

    nil
  end
end