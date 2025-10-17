class Student
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # Fields
  field :name, type: String
  field :grade, type: String
  field :student_id, type: String
  field :avatar, type: String
  field :date_of_birth, type: Date
  field :gender, type: String
  field :status, type: String, default: 'active'

  field :primary_contact_name, type: String
  field :primary_contact_relationship, type: String
  field :primary_contact_email, type: String
  field :primary_contact_phone, type: String
  field :secondary_contact_name, type: String
  field :secondary_contact_phone, type: String

  field :enrollment_date, type: Date
  field :graduation_date, type: Date
  field :homeroom, type: String
  field :special_needs, type: Array, default: []
  field :medical_notes, type: String

  # Associations
  belongs_to :school
  has_one :account, dependent: :destroy
  has_many :transactions, through: :account
  has_many :enrollments
  has_many :guardians, class_name: 'Guardian', inverse_of: :student

  # Validations
  validates :name, :grade, :school, presence: true
  validates :student_id, uniqueness: { scope: :school_id }
  validates :status, inclusion: { in: %w[active inactive graduated transferred] }
  validates :primary_contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  # Callbacks
  before_create :generate_student_id
  after_create :create_student_account

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :by_grade, ->(grade) { where(grade: grade) }
  scope :with_overdue_accounts, -> { where('account.status' => 'overdue') }

  # Indexes
  index({ school_id: 1, student_id: 1 }, unique: true)
  index({ school_id: 1, name: 1 })
  index({ school_id: 1, grade: 1, status: 1 })

  # Methods
  def full_profile
    {
      id: id.to_s,
      name: name,
      grade: grade,
      student_id: student_id,
      avatar: avatar,
      status: status,
      account_balance: account&.balance || 0,
      contact_info: {
        primary: {
          name: primary_contact_name,
          relationship: primary_contact_relationship,
          email: primary_contact_email,
          phone: primary_contact_phone
        },
        secondary: {
          name: secondary_contact_name,
          phone: secondary_contact_phone
        }
      }
    }
  end

  def active?
    status == 'active'
  end

  private

  def generate_student_id
    self.student_id ||= "#{school.schoolName[0..2].upcase}-#{SecureRandom.alphanumeric(6).upcase}"
  end

  def create_student_account
    create_account!(balance: 0, status: 'active', school_id: school_id)
  end
end
