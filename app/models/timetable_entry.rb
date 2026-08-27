# app/models/timetable_entry.rb
class TimetableEntry
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :school_id,       type: String
  field :grade_id,        type: String
  field :school_class_id, type: String
  field :subject_id,      type: String
  field :teacher_id,      type: String
  field :academic_year,   type: String, default: -> { Time.current.year.to_s }
  field :day_of_week,     type: Integer # 0 = Monday, 6 = Sunday
  field :start_minute,    type: Integer # Minutes since midnight (e.g., 540 for 09:00)
  field :end_minute,      type: Integer # Minutes since midnight (e.g., 585 for 09:45)
  field :room,            type: String

  # ===================== CONSTANTS =======================
  DAYS = %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday].freeze

  # ===================== VALIDATIONS ======================
  validates :school_id,       presence: true
  validates :grade_id,        presence: true
  validates :school_class_id, presence: true
  validates :subject_id,      presence: true
  validates :teacher_id,      presence: true
  validates :academic_year,   presence: true
  validates :day_of_week,     presence: true, inclusion: { in: 0..6 }
  validates :start_minute,    presence: true, numericality: { greater_than_or_equal_to: 0, less_than: 1440 }
  validates :end_minute,      presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 1440 }

  validate :validate_end_after_start
  validate :check_schedule_conflicts

  # ======================== INDEXES =======================
  index({ school_id: 1, academic_year: 1 })
  index({ school_class_id: 1, academic_year: 1, day_of_week: 1 })
  index({ teacher_id: 1, academic_year: 1, day_of_week: 1 })

  # ========================= SCOPES ========================
  scope :by_school,       ->(school_id) { where(school_id: school_id.to_s) }
  scope :by_class,        ->(school_class_id) { where(school_class_id: school_class_id.to_s) }
  scope :by_teacher,      ->(teacher_id) { where(teacher_id: teacher_id.to_s) }
  scope :by_academic_year, ->(year) { where(academic_year: year.to_s) }
  scope :by_day,          ->(day) { where(day_of_week: day.to_i) }

  # ========================= METHODS ========================
  def day_name
    return 'Unknown' if day_of_week.nil?
    DAYS[day_of_week] || 'Unknown'
  end

  def start_time_display
    return '' if start_minute.blank?
    format('%02d:%02d', start_minute / 60, start_minute % 60)
  end

  def end_time_display
    return '' if end_minute.blank?
    format('%02d:%02d', end_minute / 60, end_minute % 60)
  end

  def class_name
    return nil if school_class_id.blank?
    sc_str = school_class_id.to_s
    sc_bson = BSON::ObjectId.legal?(sc_str) ? BSON::ObjectId.from_string(sc_str) : nil
    SchoolClass.where(:id.in => [sc_str, sc_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving class_name for TimetableEntry #{id}: #{e.message}"
    nil
  end

  def grade_name
    return nil if grade_id.blank?
    g_str = grade_id.to_s
    g_bson = BSON::ObjectId.legal?(g_str) ? BSON::ObjectId.from_string(g_str) : nil
    Grade.where(:id.in => [g_str, g_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving grade_name for TimetableEntry #{id}: #{e.message}"
    nil
  end

  def subject_name
    return nil if subject_id.blank?
    sub_str = subject_id.to_s
    sub_bson = BSON::ObjectId.legal?(sub_str) ? BSON::ObjectId.from_string(sub_str) : nil
    Subject.where(:id.in => [sub_str, sub_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving subject_name for TimetableEntry #{id}: #{e.message}"
    nil
  end

  def teacher_name
    return nil if teacher_id.blank?
    t_str = teacher_id.to_s
    t_bson = BSON::ObjectId.legal?(t_str) ? BSON::ObjectId.from_string(t_str) : nil

    u_doc = User.collection.find(
      "$or" => [
        { "_id" => { "$in" => [t_str, t_bson].compact } },
        { "auth0_id" => t_str }
      ]
    ).first

    return nil unless u_doc
    user = User.instantiate(u_doc)
    user.try(:full_name) || user.try(:name) || "#{u_doc['name'] || u_doc['display_name']}".strip
  rescue => e
    Rails.logger.error "❌ Error resolving teacher_name for TimetableEntry #{id}: #{e.message}"
    nil
  end

  def to_api_hash
    {
      id: id.to_s,
      school_id: school_id.to_s,
      grade_id: grade_id.to_s,
      grade_name: grade_name,
      school_class_id: school_class_id.to_s,
      class_name: class_name,
      subject_id: subject_id.to_s,
      subject_name: subject_name,
      teacher_id: teacher_id.to_s,
      teacher_name: teacher_name,
      academic_year: academic_year.to_s,
      day_of_week: day_of_week,
      day_name: day_name,
      start_minute: start_minute,
      end_minute: end_minute,
      start_time_display: start_time_display,
      end_time_display: end_time_display,
      room: room,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  private

  def validate_end_after_start
    return if start_minute.blank? || end_minute.blank?
    if end_minute <= start_minute
      errors.add(:end_minute, "must be greater than start_minute")
    end
  end

  def check_schedule_conflicts
    return if day_of_week.blank? || start_minute.blank? || end_minute.blank? || academic_year.blank?

    # Find entries on the same day & academic_year whose range overlaps with [start_minute, end_minute)
    base_scope = TimetableEntry.where(
      academic_year: academic_year.to_s,
      day_of_week: day_of_week.to_i,
      :start_minute.lt => end_minute,
      :end_minute.gt => start_minute
    )

    base_scope = base_scope.where(:_id.ne => id) if persisted?

    if school_class_id.present?
      class_conflict = base_scope.where(school_class_id: school_class_id.to_s).first
      if class_conflict
        c_name = class_conflict.class_name || "Class"
        s_name = class_conflict.subject_name || "another subject"
        errors.add(:base, "#{c_name} already scheduled #{class_conflict.start_time_display}-#{class_conflict.end_time_display} for #{s_name} on #{day_name}")
      end
    end

    if teacher_id.present?
      teacher_conflict = base_scope.where(teacher_id: teacher_id.to_s).first
      if teacher_conflict
        t_name = teacher_conflict.teacher_name || "Teacher"
        c_name = teacher_conflict.class_name || "another class"
        errors.add(:base, "#{t_name} already scheduled #{teacher_conflict.start_time_display}-#{teacher_conflict.end_time_display} for #{c_name} on #{day_name}")
      end
    end
  end
end
