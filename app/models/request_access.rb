class RequestAccess
  include Mongoid::Document
  include Mongoid::Timestamps

  # Constants
  STATUSES = %w[Pending Approved Rejected].freeze
  ROLES = %w[Admin Teacher Student Viewer Parent].freeze # Added "Parent"

  # Fields
  field :school_id, type: BSON::ObjectId
  field :user_id, type: BSON::ObjectId
  field :logged_in_user_email, type: String
  field :reason, type: String
  field :requested_at, type: DateTime, default: -> { Time.now }
  field :accepted_by, type: String
  field :status, type: String, default: "Pending"
  field :rejected_by, type: String
  field :role, type: String # Stores the approved user's role

  # Relationships
  belongs_to :school, class_name: "School", inverse_of: :access_requests
  belongs_to :user, class_name: "User", inverse_of: :access_requests

  # Validations
  validates :logged_in_user_email, presence: true
  validates :reason, presence: true
  validates :user_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }, allow_nil: true # Role must be valid if present
end
