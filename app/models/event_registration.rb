class EventRegistration
  include Mongoid::Document
  include Mongoid::Timestamps

  # Associations
  belongs_to :event
  belongs_to :user

  # Fields
  field :status, type: String, default: 'registered' # could be 'registered', 'cancelled', 'attended'

  # Validations
  validates :event_id, :user_id, presence: true
  validates :status, inclusion: { in: %w[registered cancelled attended] }

  # Prevent duplicate registration for same user & event
  validates_uniqueness_of :user_id, scope: :event_id
end
