class Student
  include Mongoid::Document
  include Mongoid::Timestamps

  # Core fields
  field :name, type: String
  field :grade, type: String
  field :student_id, type: String
  field :status, type: String, default: 'active'
  field :primary_contact_email, type: String

  # Associations
  belongs_to :school
  has_one :account, dependent: :destroy
  has_many :enrollments
  has_many :guardians, class_name: 'Guardian', inverse_of: :student

  # Access transactions via account (Mongoid way)
  def transactions
    account ? account.transactions : []
  end

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

  private

  def generate_student_id
    self.student_id ||= "#{school.schoolName[0..2].upcase}-#{SecureRandom.alphanumeric(6).upcase}"
  end

  def create_student_account
    create_account!(balance: 0, status: 'active', school_id: school_id)
  end
end
