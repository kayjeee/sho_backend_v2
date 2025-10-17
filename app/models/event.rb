class Event
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  EVENT_TYPES = %w[academic sports cultural social meeting other].freeze
  AUDIENCE_TYPES = %w[all students parents teachers staff public].freeze

  # Fields
  field :title, type: String
  field :description, type: String
  field :event_type, type: String, default: 'other'
  field :start_time, type: DateTime
  field :end_time, type: DateTime
  field :location, type: String
  field :audience, type: String, default: 'all'
  field :is_published, type: Boolean, default: false
  field :registration_required, type: Boolean, default: false
  field :max_attendees, type: Integer
  field :featured_image, type: String
  field :organizer, type: String
  field :contact_email, type: String
  field :contact_phone, type: String
  field :metadata, type: Hash

  # Associations
  belongs_to :school
  has_many :registrations, class_name: 'EventRegistration', dependent: :destroy

  # Validations
  validates :title, :start_time, :school, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :audience, inclusion: { in: AUDIENCE_TYPES }
  validates :max_attendees, numericality: { greater_than: 0 }, allow_nil: true
  validate :end_time_after_start_time

  # Scopes
  scope :upcoming, -> { where(:start_time.gte => Time.current).order_by(start_time: :asc) }
  scope :past, -> { where(:start_time.lt => Time.current).order_by(start_time: :desc) }
  scope :published, -> { where(is_published: true) }
  scope :for_audience, ->(audience) { where(audience: audience) }

  # Methods
  def duration
    return 0 unless end_time && start_time
    ((end_time - start_time) / 60).to_i
  end

  def registered_count
    registrations.count
  end

  def spots_available
    max_attendees ? max_attendees - registered_count : nil
  end

  def attendees
    User.where(:id.in => registrations.pluck(:user_id))
  end

  private

  def end_time_after_start_time
    return unless end_time && start_time
    errors.add(:end_time, 'must be after start time') if end_time <= start_time
  end
end
