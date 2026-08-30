# app/models/result.rb
class Result
  include Mongoid::Document
  include Mongoid::Timestamps

  # ======================== FIELDS ========================
  field :assessment_id, type: String
  field :learner_id,    type: String
  field :score,         type: Float

  belongs_to :assessment, class_name: 'Assessment', foreign_key: :assessment_id, optional: true

  # ===================== VALIDATIONS ======================
  validates :assessment_id, presence: true
  validates :learner_id,    presence: true
  validates :score,         presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :score_does_not_exceed_max_score

  # ======================== INDEXES =======================
  index({ assessment_id: 1, learner_id: 1 }, { unique: true })
  index({ learner_id: 1 })

  # ========================= SCOPES ========================
  scope :by_assessment, ->(assessment_id) { where(assessment_id: assessment_id.to_s) }
  scope :by_learner,    ->(learner_id) { where(learner_id: learner_id.to_s) }

  # ========================= METHODS ========================
  def target_assessment
    @target_assessment ||= begin
      if assessment_id.present?
        a_str = assessment_id.to_s
        a_bson = BSON::ObjectId.legal?(a_str) ? BSON::ObjectId.from_string(a_str) : nil
        Assessment.where(:id.in => [a_str, a_bson].compact).first
      end
    end
  end

  def percentage
    return 0.0 unless score.present? && target_assessment&.max_score.to_f > 0
    ((score / target_assessment.max_score.to_f) * 100).round(2)
  end

  def learner_name
    return nil if learner_id.blank?

    lid_str = learner_id.to_s
    lid_bson = BSON::ObjectId.legal?(lid_str) ? BSON::ObjectId.from_string(lid_str) : nil

    doc = Learner.collection.find(
      "_id" => { "$in" => [lid_str, lid_bson].compact }
    ).first

    return nil unless doc

    learner = Learner.instantiate(doc)
    learner.try(:full_name) || "#{doc['first_name'] || doc['firstName']} #{doc['last_name'] || doc['lastName']}".strip
  rescue => e
    Rails.logger.error "❌ Error resolving learner_name for Result #{id}: #{e.message}"
    nil
  end

  def to_api_hash
    ass = target_assessment
    {
      id: id.to_s,
      assessment_id: assessment_id.to_s,
      assessment_name: ass&.name,
      max_score: ass&.max_score,
      learner_id: learner_id.to_s,
      learner_name: learner_name,
      score: score,
      percentage: percentage,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end

  private

  def score_does_not_exceed_max_score
    return if score.blank? || target_assessment.nil? || target_assessment.max_score.blank?

    if score > target_assessment.max_score
      errors.add(:score, "cannot exceed maximum score of #{target_assessment.max_score}")
    end
  end
end
