# app/models/invitation.rb
class Invitation
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  # ===================== ASSOCIATIONS =====================
  belongs_to :sender, class_name: 'User', optional: true
  belongs_to :school, foreign_key: :school_id, optional: true

  # ===================== CORE INVITATION FIELDS =====================
  field :school_id, type: String
  field :token, type: String
  field :status, type: String, default: 'pending'
  field :recipient_phone_number, type: String
  field :role, type: String, default: 'parent'
  field :invited_via, type: String, default: 'whatsapp'
  field :parent_name, type: String
  field :grade_id, type: String
  field :sender_email, type: String

  # ===================== TEACHER INVITATION FIELDS =====================
  field :assigned_grade_ids, type: Array, default: []
  field :subject_ids, type: Array, default: []
  field :teacher_type, type: String, default: 'staff'

  # ===================== LEARNER INFORMATION =====================
  field :learner_number, type: String
  field :learner_numbers, type: Array, default: []
  field :learner_ids, type: Array, default: []
  field :learner_names, type: Array, default: []

  # ===================== TIMESTAMP FIELDS =====================
  field :accepted_at, type: Time
  field :expires_at, type: Time

  # ===================== ADDITIONAL DATA =====================
  field :metadata, type: Hash, default: {}
  field :notes, type: String
  field :invitation_type, type: String, default: 'standard'
  field :magic_link_sent_at, type: Time

  # ===================== VALIDATIONS =====================
  validates :token, presence: true, uniqueness: true
  validates :recipient_phone_number, presence: true
  validates :role, presence: true, inclusion: { in: %w[parent teacher admin student] }
  validates :status, inclusion: { in: %w[pending accepted expired rejected cancelled] }
  validates :invited_via, inclusion: { in: %w[whatsapp sms email direct link] }
  validates :teacher_type, inclusion: { in: %w[staff community] }, allow_nil: true
  validate :validate_learner_data_consistency
  validate :validate_phone_number_format

  # ===================== INDEXES =====================
  index({ token: 1 }, { unique: true })
  index({ status: 1 })
  index({ role: 1 })
  index({ recipient_phone_number: 1 })
  index({ school_id: 1 })
  index({ sender_id: 1 })
  index({ created_at: -1 })
  index({ expires_at: 1 })
  index({ accepted_at: 1 })
  index({ magic_link_sent_at: 1 })

  # Multi-field indexes
  index({ status: 1, expires_at: 1 })
  index({ school_id: 1, status: 1 })
  index({ recipient_phone_number: 1, status: 1 })
  index({ learner_ids: 1 })
  index({ learner_numbers: 1 })
  index({ learner_ids: 1, status: 1 })
  index({ token: 1, status: 1 })

  # ===================== CALLBACKS =====================
  before_validation :generate_token, unless: :token?
  before_create :set_default_expiration
  before_save :sync_legacy_learner_fields
  after_save :update_status_if_expired

  # ===================== SCOPES =====================
  scope :pending, -> { where(status: 'pending') }
  scope :accepted, -> { where(status: 'accepted') }
  scope :expired, -> { where(status: 'expired') }
  scope :rejected, -> { where(status: 'rejected') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :active, -> { pending.where(:expires_at.gt => Time.current) }
  scope :inactive, -> { where(:status.in => ['accepted', 'rejected', 'cancelled', 'expired']) }

  scope :by_school, ->(school_id) {
    if school_id.present?
      resolved_str = school_id.to_s
      if BSON::ObjectId.legal?(resolved_str)
        any_of({ school_id: resolved_str }, { school_id: BSON::ObjectId.from_string(resolved_str) })
      else
        where(school_id: resolved_str)
      end
    else
      all
    end
  }
  scope :by_sender, ->(sender_id) { where(sender_id: sender_id) }
  scope :by_recipient_phone, ->(phone) { where(recipient_phone_number: phone) }
  scope :by_learner_id, ->(learner_id) { where(learner_ids: learner_id) }
  scope :by_learner_number, ->(number) { where(learner_numbers: number) }
  scope :by_role, ->(role_name) { where(role: role_name.to_s.downcase) if role_name.present? }
  scope :with_token, ->(token) { where(token: token) }

  scope :recent, -> { order(created_at: :desc) }
  scope :expiring_soon, ->(hours = 24) {
    pending.where(:expires_at.lte => hours.hours.from_now, :expires_at.gt => Time.current)
  }
  scope :expired_auto, -> { pending.where(:expires_at.lte => Time.current) }
  scope :not_sent, -> { where(magic_link_sent_at: nil) }

  # ===================== CLASS METHODS =====================

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def self.find_by_token(token)
    where(token: token).first
  end

  def self.create_for_learners(learners_data, invitation_params)
    invitations = []

    learners_data.each_slice(50) do |batch|
      batch.each do |learner_data|
        invitation = new(invitation_params.merge(
          learner_ids: [learner_data[:id]],
          learner_numbers: [learner_data[:accession_number]],
          learner_names: [learner_data[:name]],
          learner_number: learner_data[:accession_number]
        ))

        invitations << invitation if invitation.save
      end
    end

    invitations
  end

  def self.build_magic_link(token, school_name)
    return nil unless token.present? && school_name.present?

    encoded_school = URI.encode_www_form_component(school_name.to_s.strip)
    "?token=#{token}&school=#{encoded_school}"
  end

  def self.find_by(conditions = {})
    where(conditions).first
  end

  # ===================== INSTANCE METHODS =====================

  def valid_invitation?
    status == 'pending' && !expired?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def accept!
    update(status: 'accepted', accepted_at: Time.current)
  end

  def expire!
    update(status: 'expired')
  end

  def reject!
    update(status: 'rejected')
  end

  def cancel!
    update(status: 'cancelled')
  end

  def extend_expiration!(days = 7)
    update(expires_at: (expires_at || Time.current) + days.days)
  end

  def resend!
    new_token = self.class.generate_token
    update(
      token: new_token,
      status: 'pending',
      expires_at: 7.days.from_now,
      accepted_at: nil,
      magic_link_sent_at: nil
    )
  end

  def mark_as_sent!
    update(magic_link_sent_at: Time.current)
  end

  def sender_name
    sender&.full_name || sender&.name || 'System'
  end

  def school_name
    school&.schoolName || school&.name || 'Unknown School'
  end

  def grade_name
    return nil if grade_id.blank?

    gid_str = grade_id.to_s
    gid_bson = BSON::ObjectId.legal?(gid_str) ? BSON::ObjectId.from_string(gid_str) : nil

    Grade.where(:id.in => [gid_str, gid_bson].compact).first&.name
  rescue => e
    Rails.logger.error "❌ Error resolving grade_name for invitation #{id}: #{e.message}"
    nil
  end

  def assigned_grade_names
    return [] if assigned_grade_ids.blank?

    gid_strings = Array(assigned_grade_ids).map(&:to_s).reject(&:blank?)
    return [] if gid_strings.empty?

    gid_bsons = gid_strings.map { |s| BSON::ObjectId.legal?(s) ? BSON::ObjectId.from_string(s) : nil }.compact
    all_ids = (gid_strings + gid_bsons).uniq

    found_grades = Grade.where(:id.in => all_ids).to_a
    grade_map = found_grades.each_with_object({}) do |g, hash|
      hash[g.id.to_s] = g.name
    end

    gid_strings.map { |gid| grade_map[gid] }.compact
  rescue => e
    Rails.logger.error "❌ Error resolving assigned_grade_names for invitation #{id}: #{e.message}"
    []
  end

  def subject_names
    return [] if subject_ids.blank?

    sub_strings = Array(subject_ids).map(&:to_s).reject(&:blank?)
    return [] if sub_strings.empty?

    sub_bsons = sub_strings.map { |s| BSON::ObjectId.legal?(s) ? BSON::ObjectId.from_string(s) : nil }.compact
    all_ids = (sub_strings + sub_bsons).uniq

    found_subjects = Subject.where(:id.in => all_ids).to_a
    sub_map = found_subjects.each_with_object({}) do |s, hash|
      hash[s.id.to_s] = s.name
    end

    sub_strings.map { |sid| sub_map[sid] }.compact
  rescue => e
    Rails.logger.error "❌ Error resolving subject_names for invitation #{id}: #{e.message}"
    []
  end

  def resolved_learner_names
    stored_names = Array(learner_names).map(&:to_s).map(&:strip).reject(&:blank?)
    return stored_names if stored_names.present?

    if learner_ids.present? && learner_ids.any?
      lid_strings = learner_ids.map(&:to_s)
      lid_bsons = lid_strings.map { |s| BSON::ObjectId.legal?(s) ? BSON::ObjectId.from_string(s) : nil }.compact

      found_learners = Learner.where(:id.in => (lid_strings + lid_bsons)).to_a
      names = found_learners.map(&:full_name).reject(&:blank?)
      return names if names.present?
    end

    numbers = (Array(learner_numbers) + [learner_number]).map(&:to_s).map(&:strip).reject(&:blank?).uniq
    if numbers.present?
      school_id_str = school_id.to_s
      school_id_bson = BSON::ObjectId.legal?(school_id_str) ? BSON::ObjectId.from_string(school_id_str) : nil
      school_ids = [school_id_str, school_id_bson].compact

      query = {
        "$or" => [
          { "accessionNumber" => { "$in" => numbers } },
          { "accession_number" => { "$in" => numbers } }
        ]
      }
      query["school_id"] = { "$in" => school_ids } if school_ids.present?

      docs = Learner.collection.find(query).to_a
      found_learners = docs.map { |doc| Learner.instantiate(doc) }
      names = found_learners.map(&:full_name).reject(&:blank?)
      return names if names.present?
    end

    []
  rescue => e
    Rails.logger.error "❌ Error resolving resolved_learner_names for invitation #{id}: #{e.message}"
    []
  end

  def multiple_learners?
    learner_ids.present? && learner_ids.size > 1
  end

  def learner_count
    learner_ids&.size || (learner_number.present? ? 1 : 0)
  end

  def learner_names_display
    return 'No learners' if learner_names.blank?

    case learner_names.size
    when 1
      learner_names.first
    when 2
      learner_names.join(' and ')
    else
      "#{learner_names[0..-2].join(', ')}, and #{learner_names.last}"
    end
  end

  def primary_learner
    {
      id: learner_ids&.first,
      number: learner_numbers&.first || learner_number,
      name: learner_names&.first
    }
  end

  def add_learner(learner_id, learner_number, learner_name)
    self.learner_ids ||= []
    self.learner_numbers ||= []
    self.learner_names ||= []

    unless learner_ids.include?(learner_id)
      self.learner_ids << learner_id
      self.learner_numbers << learner_number
      self.learner_names << learner_name

      self.learner_number = learner_number if self.learner_number.blank?
    end

    save
  end

  def remove_learner(learner_id)
    return false unless learner_ids.include?(learner_id)

    index = learner_ids.index(learner_id)
    self.learner_ids.delete_at(index)
    self.learner_numbers.delete_at(index)
    self.learner_names.delete_at(index)

    self.learner_number = learner_numbers.first if learner_number == learner_id.to_s

    save
  end

  def to_api_hash(include_token: true)
    hash = {
      id: id.to_s,
      token: token,
      recipient_phone_number: recipient_phone_number,
      role: role,
      status: status,
      invited_via: invited_via,
      parent_name: parent_name,
      school_id: school_id&.to_s,
      school_name: school_name,
      sender_id: sender_id&.to_s,
      sender_name: sender_name,
      sender_email: sender_email,
      learner_number: learner_number,
      learner_numbers: learner_numbers,
      learner_ids: learner_ids,
      learner_names: resolved_learner_names,
      learner_count: learner_count,
      multiple_learners: multiple_learners?,
      grade_id: grade_id,
      grade_name: grade_name,
      assigned_grade_ids: Array(assigned_grade_ids).map(&:to_s),
      assigned_grade_names: assigned_grade_names,
      subject_ids: Array(subject_ids).map(&:to_s),
      subject_names: subject_names,
      teacher_type: teacher_type || 'staff',
      accepted_at: accepted_at&.iso8601,
      expires_at: expires_at&.iso8601,
      expired: expired?,
      valid: valid_invitation?,
      invitation_type: invitation_type,
      metadata: metadata,
      magic_link_sent_at: magic_link_sent_at&.iso8601,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }

    hash[:magic_link_query] = self.class.build_magic_link(token, school_name)
    hash[:full_magic_link] = "https://www.schoolheadoffice.com/parent#{hash[:magic_link_query]}"

    hash
  end

  def to_notification_hash
    {
      id: id.to_s,
      token: token,
      recipient_phone_number: recipient_phone_number,
      learner_names: learner_names_display,
      school_name: school_name,
      expires_at: expires_at&.strftime('%b %d, %Y'),
      invitation_link: Rails.application.routes.url_helpers.accept_invitation_url(token: token),
      magic_link_query: self.class.build_magic_link(token, school_name)
    }
  end

  def magic_link_sent?
    magic_link_sent_at.present?
  end

  private

  def generate_token
    self.token ||= self.class.generate_token
  end

  def set_default_expiration
    self.expires_at ||= 7.days.from_now
  end

  def update_status_if_expired
    if status == 'pending' && expired?
      self.status = 'expired'
      save(validate: false) rescue nil
    end
  end

  def sync_legacy_learner_fields
    if learner_number.blank? && learner_numbers.present?
      self.learner_number = learner_numbers.first
    end

    if learner_number.present? && learner_ids.blank?
      self.learner_ids = [learner_number]
      self.learner_numbers = [learner_number]
      self.learner_names = [learner_number]
    end
  end

  def validate_learner_data_consistency
    return if learner_ids.blank? && learner_number.blank?

    if learner_ids.present?
      if learner_numbers.present? && learner_ids.length != learner_numbers.length
        errors.add(:learner_numbers, "must have same count as learner_ids")
      end

      if learner_names.present? && learner_ids.length != learner_names.length
        errors.add(:learner_names, "must have same count as learner_ids")
      end
    end
  end

  def validate_phone_number_format
    return if recipient_phone_number.blank?

    unless recipient_phone_number.match?(/\A27\d{9}\z/)
      errors.add(:recipient_phone_number, "must be a valid South African number (27XXXXXXXXX)")
    end
  end
end
