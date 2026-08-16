# app/models/teacher_invitation.rb
class TeacherInvitation
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :teacher_email,         type: String
  field :invitation_token,      type: String
  field :status,                type: Integer, default: 0
  field :assigned_grades,       type: Array, default: []
  field :invitation_data,       type: Hash, default: {}
  field :invited_at,            type: DateTime
  field :expires_at,            type: DateTime
  field :accepted_at,           type: DateTime

  # ===================== CONSTANTS =======================
  STATUSES = {
    'pending' => 0,
    'accepted' => 1,
    'declined' => 2,
    'expired' => 3,
    'cancelled' => 4
  }.freeze

  # ===================== VALIDATIONS ======================
  validates :teacher_email,     presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :invitation_token,  presence: true, uniqueness: true
  validates :status,            inclusion: { in: STATUSES.values }
  validates :expires_at,        presence: true
  validates :school_id,         presence: true
  validates :invited_by_id,     presence: true

  validate :expiration_date_future
  validate :grades_belong_to_school

  # ===================== ASSOCIATIONS =====================
  belongs_to :school,           class_name: 'School'
  belongs_to :invited_by,       class_name: 'User'
  belongs_to :teacher,          class_name: 'User', optional: true

  # ======================== INDEXES =======================
  index({ invitation_token: 1 }, { unique: true })
  index({ school_id: 1, status: 1 })
  index({ teacher_email: 1, school_id: 1 })
  index({ expires_at: 1 })

  # ========================= SCOPES ========================
  scope :pending,               -> { where(status: 0) }
  scope :accepted,              -> { where(status: 1) }
  scope :declined,              -> { where(status: 2) }
  scope :expired,               -> { where(status: 3) }
  scope :cancelled,             -> { where(status: 4) }
  scope :active,                -> { where(status: [0, 1]) }
  scope :by_school,             ->(school_id) { where(school_id: school_id) }
  scope :expiring_soon,         -> { pending.where(:expires_at.lte => 24.hours.from_now) }

  # ======================== CALLBACKS =======================
  before_validation :generate_token, if: -> { invitation_token.blank? }
  before_validation :set_invited_at, if: -> { invited_at.blank? }
  before_validation :set_expiration, if: -> { expires_at.blank? }
  before_save :check_expiration

  # ========================= METHODS ========================

  # Status helper methods
  def pending?
    status == 0
  end

  def accepted?
    status == 1
  end

  def declined?
    status == 2
  end

  def expired?
    status == 3 || (expires_at.present? && expires_at.to_time < Time.current)
  end

  def cancelled?
    status == 4
  end

  def status_text
    STATUSES.key(status) || 'unknown'
  end

  # Invitation actions
  def accept!(teacher_params = {})
    return false unless pending? && !expired?

    transaction do
      # Find or create teacher user
      teacher_user = User.find_by(email: teacher_email)

      if teacher_user.nil?
        teacher_user = User.create!(
          email: teacher_email,
          name: teacher_params[:name] || teacher_email.split('@').first.humanize,
          roles: ['Teacher'],
          **teacher_params
        )
      end

      # Add school to teacher's schools
      teacher_user.add_school(school_id.to_s)

      # Create teacher-school role
      UserSchoolRole.create!(
        user: teacher_user,
        school: school,
        role: 'Teacher',
        status: 0,
        assigned_at: Time.current
      )

      # Create grade assignments
      assigned_grades.each do |grade_id|
        TeacherGradeAssignment.create!(
          teacher: teacher_user,
          grade_id: grade_id,
          school: school,
          assigned_by: invited_by,
          role_type: 'primary',
          status: 0,
          assigned_at: Time.current
        )
      end

      update!(
        status: 1,
        accepted_at: Time.current,
        teacher: teacher_user
      )

      Rails.logger.info "✅ Teacher invitation accepted: #{teacher_email} for school #{school.schoolName}"
      true
    end
  rescue => e
    Rails.logger.error "❌ Failed to accept teacher invitation #{invitation_token}: #{e.message}"
    false
  end

  def decline!(reason = nil)
    return false unless pending?

    update!(
      status: 2,
      invitation_data: invitation_data.merge(declined_reason: reason)
    )

    Rails.logger.info "❌ Teacher invitation declined: #{teacher_email} for school #{school.schoolName}"
    true
  end

  def cancel!(reason = nil)
    return false unless pending?

    update!(
      status: 4,
      invitation_data: invitation_data.merge(cancelled_reason: reason)
    )

    Rails.logger.info "🚫 Teacher invitation cancelled: #{teacher_email} for school #{school.schoolName}"
    true
  end

  # Utility methods
  def assigned_grade_names
    return [] if assigned_grades.empty?

    Grade.where(:_id.in => assigned_grades.map { |id| BSON::ObjectId.from_string(id) })
         .pluck(:name)
  end

  def days_until_expiry
    return 0 if expired?
    return 0 if expires_at.blank?
    exp_time = expires_at.respond_to?(:to_time) ? expires_at.to_time : expires_at
    ((exp_time - Time.current.to_time) / 1.day).ceil
  end

  def invitation_url
    Rails.application.routes.url_helpers.accept_teacher_invitation_url(
      token: invitation_token,
      host: Rails.application.config.app_host
    )
  rescue
    nil
  end

  def to_api_hash
    {
      id: id.to_s,
      invitation_token: invitation_token,
      token: invitation_token,
      teacher_email: teacher_email,
      status: status,
      status_text: status_text,
      school: {
        id: school_id.to_s,
        name: school&.schoolName
      },
      assigned_grades: assigned_grades,
      assigned_grade_names: assigned_grade_names,
      invited_by: {
        id: invited_by_id.to_s,
        name: invited_by&.name
      },
      teacher: teacher&.name,
      invited_at: invited_at,
      expires_at: expires_at,
      accepted_at: accepted_at,
      days_until_expiry: days_until_expiry,
      invitation_data: invitation_data,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def generate_token
    self.invitation_token = SecureRandom.urlsafe_base64(32)
  end

  def set_invited_at
    self.invited_at = Time.current
  end

  def set_expiration
    self.expires_at = 14.days.from_now # Teachers get longer to respond
  end

  def check_expiration
    if pending? && expires_at < Time.current
      self.status = 3 # expired
    end
  end

  def expiration_date_future
    return unless expires_at
    if expires_at < Time.current
      errors.add(:expires_at, 'must be in the future')
    end
  end

  def grades_belong_to_school
    return if assigned_grades.empty?

    valid_grade_ids = Grade.where(school_id: school_id).pluck(:id).map(&:to_s)
    invalid_ids = assigned_grades.reject { |gid| valid_grade_ids.include?(gid.to_s) }

    if invalid_ids.any?
      errors.add(:assigned_grades, "contain invalid grades not belonging to this school: #{invalid_ids.join(', ')}")
    end
  end
end
