# app/models/user.rb - Updated with grade associations
class User
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :name,             type: String               
  field :email,            type: String               
  field :auth0_id,         type: String               
  field :roles,            type: Array,  default: []   
  field :cash_account,     type: Float,  default: 0.0  
  field :payment_history,  type: Array,  default: []   

  # ===================== VALIDATIONS ======================
  validates :email,        presence: true, uniqueness: true
  validates :auth0_id,     presence: true, uniqueness: true

  # ===================== ASSOCIATIONS =====================
  has_many :conversations,       foreign_key: :user_id
  has_many :accounts,            class_name: 'Account', inverse_of: :user
  has_many :sent_messages,       class_name: 'Message', inverse_of: :sender
  has_many :messages,            inverse_of: :user
  has_many :received_messages,   class_name: 'Message', inverse_of: :receiver
  has_many :user_school_roles,   class_name: 'UserSchoolRole', inverse_of: :user

  # NEW GRADE-RELATED ASSOCIATIONS
  has_many :created_grades,      class_name: 'Grade', inverse_of: :created_by
  has_many :created_learners,    class_name: 'Learner', inverse_of: :created_by
  has_many :learner_invitations_sent, class_name: 'LearnerInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_sent, class_name: 'TeacherInvitation', inverse_of: :invited_by
  has_many :teacher_invitations_received, class_name: 'TeacherInvitation', inverse_of: :teacher
  has_many :teacher_grade_assignments, class_name: 'TeacherGradeAssignment', inverse_of: :teacher
  has_many :assigned_teacher_roles, class_name: 'TeacherGradeAssignment', inverse_of: :assigned_by

  has_and_belongs_to_many :schools, class_name: 'School', inverse_of: :users, validate: false

  # ======================== CALLBACKS =======================
  before_save :log_school_id_changes, if: :school_ids_changed?

  # ========================= METHODS ========================

  # NEW GRADE-RELATED METHODS
  def teaching_grades
    Grade.joins(:teacher_grade_assignments)
         .where(teacher_grade_assignments: { teacher_id: id, status: 0 })
  end

  def primary_teaching_grades
    teaching_grades.where(teacher_grade_assignments: { role_type: 'primary' })
  end

  def assistant_teaching_grades
    teaching_grades.where(teacher_grade_assignments: { role_type: 'assistant' })
  end

  def can_access_grade?(grade)
    return true if roles.include?('Admin')
    return true if created_grades.include?(grade)
    return true if teaching_grades.include?(grade)
    
    # Check if user is admin in the grade's school
    user_school_roles.find_by(
      school: grade.school,
      role: 'Admin',
      status: 0
    ).present?
  end

  def grades_in_school(school)
    return school.grades if roles.include?('Admin')
    
    # Return grades user created or teaches in this school
    created_in_school = created_grades.where(school: school)
    teaching_in_school = teaching_grades.where(school: school)
    
    Grade.where(:_id.in => (created_in_school.pluck(:id) + teaching_in_school.pluck(:id)).uniq)
  end

  # EXISTING METHODS (keeping your original implementation)
  def add_school(school_id_string)
    Rails.logger.debug "🏫 User#add_school: Attempting to add school with ID string '#{school_id_string}' to user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#add_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_add = School.find_by(_id: school_bson_id)

    unless school_to_add
      Rails.logger.warn "⚠️ User#add_school: School with ID '#{school_id_string}' not found in database. Cannot associate."
      errors.add(:schools, "School not found.")
      return false
    end

    if self.schools.include?(school_to_add)
      Rails.logger.info "✅ User#add_school: School '#{school_id_string}' is already associated with user #{id}. No action taken."
      return true
    end

    self.schools << school_to_add

    if save
      Rails.logger.info "✅ User#add_school: Successfully associated school '#{school_id_string}' with user #{id}."
      true
    else
      Rails.logger.error "❌ User#add_school: Failed to save user #{id} after associating school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def remove_school(school_id_string)
    Rails.logger.debug "➖ User#remove_school: Attempting to remove school with ID string '#{school_id_string}' from user #{id}"

    begin
      school_bson_id = BSON::ObjectId.from_string(school_id_string.to_s.strip)
    rescue BSON::ObjectId::Invalid
      Rails.logger.error "❌ User#remove_school: Invalid BSON::ObjectId string provided: '#{school_id_string}'."
      errors.add(:schools, "Invalid school ID format.")
      return false
    end

    school_to_remove = self.schools.find_by(_id: school_bson_id)

    unless school_to_remove
      Rails.logger.warn "⚠️ User#remove_school: School with ID '#{school_id_string}' not found in user's associations for user #{id}."
      return false
    end

    self.schools.delete(school_to_remove)

    if save
      Rails.logger.info "🗑️ User#remove_school: Successfully removed school '#{school_id_string}' from user #{id}."
      true
    else
      Rails.logger.error "❌ User#remove_school: Failed to save user #{id} after removing school '#{school_id_string}'. Errors: #{errors.full_messages.join(', ')}"
      false
    end
  end

  private

  def log_school_id_changes
    old_school_ids, new_school_ids = changes_to_save['school_ids']

    old_school_ids = old_school_ids || []
    new_school_ids = new_school_ids || []

    old_school_ids_str = old_school_ids.map(&:to_s)
    new_school_ids_str = new_school_ids.map(&:to_s)

    added   = new_school_ids_str - old_school_ids_str
    removed = old_school_ids_str - new_school_ids_str

    Rails.logger.debug "🔄 User#log_school_id_changes: Associated schools updated for user #{id}:"
    Rails.logger.debug "  OLD (IDs): #{old_school_ids_str.inspect}"
    Rails.logger.debug "  NEW (IDs): #{new_school_ids_str.inspect}"
    Rails.logger.debug "  ➕ ADDED (IDs): #{added.inspect}"   if added.any?
    Rails.logger.debug "  ➖ REMOVED (IDs): #{removed.inspect}" if removed.any?
  end
end

# app/models/learner.rb - Updated with enhanced grade association
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
  field :date_of_birth,     type: Date
  field :enrollment_date,   type: Date
  field :parent_info,       type: Hash, default: {}

  # ===================== VALIDATIONS ======================
  validates :first_name, :last_name, presence: true
  validates :accession_number, uniqueness: { scope: :school_id }, allow_blank: true

  GENDERS = { 'male' => 0, 'female' => 1, 'other' => 2 }.freeze
  STATUSES = { 'active' => 0, 'inactive' => 1, 'graduated' => 2, 'transferred' => 3, 'expelled' => 4 }.freeze

  validates :gender, inclusion: { in: GENDERS.values }
  validates :status, inclusion: { in: STATUSES.values }

  # GRADE-SPECIFIC VALIDATIONS
  validate :age_meets_grade_requirements, if: -> { grade.present? && date_of_birth.present? }
  validate :grade_belongs_to_school

  # ===================== ASSOCIATIONS =====================
  belongs_to :school, class_name: 'School', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :grade, class_name: 'Grade', optional: true

  # NEW ASSOCIATIONS
  has_many :learner_invitations, class_name: 'LearnerInvitation', inverse_of: :learner

  # ======================== INDEXES =======================
  index({ school_id: 1, accession_number: 1 }, { unique: true, sparse: true })
  index({ first_name: 1, last_name: 1 })
  index({ school_id: 1 })
  index({ grade_id: 1 })
  index({ status: 1 })

  # ======================== CALLBACKS =======================
  before_validation :set_default_accession_number, if: -> { accession_number.blank? }
  before_validation :sanitize_phone_numbers
  before_validation :set_enrollment_date, if: -> { enrollment_date.blank? && status == 0 }

  # ========================= SCOPES ========================
  scope :active, -> { where(status: 0) }
  scope :inactive, -> { where(status: 1) }
  scope :graduated, -> { where(status: 2) }
  scope :transferred, -> { where(status: 3) }
  scope :expelled, -> { where(status: 4) }
  scope :by_school, ->(school_id) { where(school_id: school_id) }
  scope :by_grade, ->(grade_id) { where(grade_id: grade_id) }
  scope :by_gender, ->(gender) { where(gender: gender) }

  # ========================= METHODS ========================

  # Status helper methods
  def active?
    status == 0
  end

  def inactive?
    status == 1
  end

  def graduated?
    status == 2
  end

  def transferred?
    status == 3
  end

  def expelled?
    status == 4
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  # Gender helper methods
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

  def full_name
    "#{first_name} #{last_name}".strip
  end

  # NEW GRADE-RELATED METHODS
  def age_in_months
    return nil unless date_of_birth
    
    today = Date.current
    months = (today.year - date_of_birth.year) * 12 + (today.month - date_of_birth.month)
    months -= 1 if today.day < date_of_birth.day
    months
  end

  def age_in_years
    return nil unless date_of_birth
    
    today = Date.current
    age = today.year - date_of_birth.year
    age -= 1 if today < date_of_birth + age.years
    age
  end

  def meets_grade_age_requirements?
    return true unless grade && date_of_birth
    
    age_months = age_in_months
    return true unless age_months
    
    grade.accepts_age?(age_months)
  end

  def transfer_to_grade(new_grade, transferred_by_user = nil)
    return false unless new_grade
    return false unless new_grade.can_enroll_learner?
    return false if new_grade.school != school
    
    old_grade = grade
    self.grade = new_grade
    
    if save
      Rails.logger.info "✅ Learner #{full_name} transferred from #{old_grade&.name} to #{new_grade.name}"
      true
    else
      Rails.logger.error "❌ Failed to transfer learner #{full_name}: #{errors.full_messages.join(', ')}"
      false
    end
  end

  def graduate!(graduation_date = Date.current)
    update!(
      status: 2,
      graduated_at: graduation_date
    )
    Rails.logger.info "🎓 Learner graduated: #{full_name} from #{grade&.name}"
    true
  rescue => e
    Rails.logger.error "❌ Failed to graduate learner #{full_name}: #{e.message}"
    false
  end

  # EXISTING METHODS with enhancements
  def add_school(school_id_string)
    Rails.logger.debug "🏫 Learner#add_school: Attempting to add school with ID string '#{school_id_string}' to learner #{id}"

    return false if school_id_string.blank?

    begin
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

  def school_name
    school&.schoolName || school&.name
  end

  def grade_name
    grade&.name
  end

  def primary_contact
    phone.presence || whatsapp.presence || tel_home.presence
  end

  def emergency_contact
    tel_emergency.presence || primary_contact
  end

  # Enhanced API export
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
      date_of_birth: date_of_birth,
      age: {
        years: age_in_years,
        months: age_in_months
      },
      school_id: school_id&.to_s,
      school_name: school_name,
      grade_id: grade_id&.to_s,
      grade_name: grade_name,
      meets_grade_requirements: meets_grade_age_requirements?,
      enrollment_date: enrollment_date,
      contact: {
        phone: phone,
        whatsapp: whatsapp,
        tel_home: tel_home,
        tel_emergency: tel_emergency,
        telegram: telegram
      },
      parent_info: parent_info,
      created_by: {
        id: created_by_id&.to_s,
        name: created_by&.name
      },
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def set_default_accession_number
    timestamp = Time.now.to_i.to_s.last(6)
    random_suffix = rand(100..999)
    school_prefix = school_name&.first(3)&.upcase || 'STD'
    
    self.accession_number = "#{school_prefix}#{timestamp}#{random_suffix}"
  end

  def set_enrollment_date
    self.enrollment_date = Date.current
  end

  def sanitize_phone_numbers
    %w[phone tel_emergency tel_home whatsapp telegram].each do |field|
      value = send(field)
      if value.present?
        sanitized = value.gsub(/[^\d\+\-\(\)\s]/, '')
        send("#{field}=", sanitized.strip)
      end
    end
  end

  def age_meets_grade_requirements
    return unless grade && date_of_birth
    
    unless meets_grade_age_requirements?
      age_years = age_in_years
      min_years = grade.min_age ? (grade.min_age / 12.0).round(1) : 'not set'
      max_years = grade.max_age ? (grade.max_age / 12.0).round(1) : 'not set'
      
      errors.add(:date_of_birth, 
        "Age (#{age_years} years) doesn't meet grade requirements (#{min_years} - #{max_years} years)")
    end
  end

  def grade_belongs_to_school
    return unless grade && school
    
    unless grade.school == school
      errors.add(:grade, "must belong to the same school as the learner")
    end
  end
end
