class Trip
  include Mongoid::Document
  include Mongoid::Timestamps

  # Fields
  field :title, type: String
  field :description, type: String
  field :destination, type: String
  field :departure_time, type: DateTime
  field :return_time, type: DateTime
  field :cost, type: Float
  field :max_participants, type: Integer
  field :registration_deadline, type: DateTime
  field :requirements, type: Array, default: []
  field :contact_person, type: String
  field :contact_email, type: String
  field :contact_phone, type: String
  field :is_published, type: Boolean, default: false
  field :transportation_details, type: String
  field :accommodation_details, type: String
  field :itinerary, type: Array
  field :permission_form_url, type: String

  # Associations
  belongs_to :school
  has_many :registrations, class_name: 'TripRegistration'
  # FIXED: Remove :through associations
  
  # Validations
  validates :title, :destination, :departure_time, :school_id, presence: true
  validates :cost, numericality: { greater_than_or_equal_to: 0 }
  validate :return_time_after_departure
  validate :deadline_before_departure

  # Scopes
  scope :upcoming, -> { where(:departure_time.gte => Time.current).order(departure_time: :asc) }
  scope :requires_permission, -> { where(:permission_form_url.exists => true) }

  # Methods
  def registered_count
    registrations.count
  end

  def spots_available
    max_participants ? max_participants - registered_count : nil
  end

  # Custom method to get participants
  def participants
    Student.in(id: registrations.pluck(:student_id))
  end

  # Custom method to get payments
  def payments
    Payment.in(registration_id: registrations.pluck(:id))
  end

  def total_collected
    payments.sum(:amount)
  end

  private

  def return_time_after_departure
    return unless return_time && departure_time
    errors.add(:return_time, "must be after departure time") if return_time <= departure_time
  end

  def deadline_before_departure
    return unless registration_deadline && departure_time
    errors.add(:registration_deadline, "must be before departure time") if registration_deadline >= departure_time
  end
end