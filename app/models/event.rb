class Event
  include Mongoid::Document
  include Mongoid::Timestamps

  field :title, type: String
  field :description, type: String
  field :start_time, type: DateTime
  field :end_time, type: DateTime
  field :location, type: String

  belongs_to :school
  has_many :attendees, class_name: 'Student'

  validates :title, :start_time, :end_time, :school, presence: true
end
