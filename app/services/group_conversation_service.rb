# app/services/group_conversation_service.rb
class GroupConversationService
  def self.resolve_participants(school_id, scope_type, scope_id, requesting_user_id = nil)
    school_id_str = school_id.to_s
    school_id_bson = BSON::ObjectId.legal?(school_id_str) ? BSON::ObjectId.from_string(school_id_str) : nil

    participant_uids = []

    case scope_type.to_s.downcase
    when 'class'
      return [] if scope_id.blank?

      sc_str = scope_id.to_s
      sc_bson = BSON::ObjectId.legal?(sc_str) ? BSON::ObjectId.from_string(sc_str) : nil

      school_class = SchoolClass.where(:id.in => [sc_str, sc_bson].compact).first
      return [] unless school_class

      raw_learner_ids = Array(school_class.learner_ids).map(&:to_s)
      learner_bsons = raw_learner_ids.map { |id| BSON::ObjectId.legal?(id) ? BSON::ObjectId.from_string(id) : nil }.compact

      docs = Learner.collection.find(
        "_id" => { "$in" => (raw_learner_ids + learner_bsons).uniq }
      ).to_a

      parent_bids = docs.flat_map { |d| Array(d["parent_ids"]) }.compact.uniq
      parent_uids = parent_bids.map(&:to_s)

      # Ensure resolved users are parent Users
      found_users = User.where(:id.in => (parent_bids + parent_uids).uniq, roles: "parent").pluck(:id)
      participant_uids.concat(found_users.map(&:to_s))

    when 'grade'
      return [] if scope_id.blank?

      g_str = scope_id.to_s
      g_bson = BSON::ObjectId.legal?(g_str) ? BSON::ObjectId.from_string(g_str) : nil

      docs = Learner.collection.find(
        "$or" => [
          { "gradeId" => { "$in" => [g_str, g_bson].compact } },
          { "grade_id" => { "$in" => [g_str, g_bson].compact } }
        ]
      ).to_a

      parent_bids = docs.flat_map { |d| Array(d["parent_ids"]) }.compact.uniq
      parent_uids = parent_bids.map(&:to_s)

      found_users = User.where(:id.in => (parent_bids + parent_uids).uniq, roles: "parent").pluck(:id)
      participant_uids.concat(found_users.map(&:to_s))

    when 'school'
      docs = Learner.collection.find(
        "school_id" => { "$in" => [school_id_str, school_id_bson].compact }
      ).to_a

      parent_bids = docs.flat_map { |d| Array(d["parent_ids"]) }.compact.uniq
      parent_uids = parent_bids.map(&:to_s)

      found_users = User.where(:id.in => (parent_bids + parent_uids).uniq, roles: "parent").pluck(:id)
      participant_uids.concat(found_users.map(&:to_s))

    when 'teachers'
      # Users with 'teacher' in roles linked to school
      teacher_users = User.where(roles: "teacher").any_of(
        { school_ids: school_id_str },
        { school_ids: school_id_bson }
      ).pluck(:id)

      # Also check TeacherGradeAssignment records for school
      tga_teacher_ids = TeacherGradeAssignment.by_school(school_id_str).pluck(:teacher_id)

      all_t_bids = (teacher_users + tga_teacher_ids).compact.uniq
      all_t_uids = all_t_bids.map(&:to_s)

      found_users = User.where(:id.in => (all_t_bids + all_t_uids).uniq, roles: "teacher").pluck(:id)
      participant_uids.concat(found_users.map(&:to_s))

    when 'self'
      if requesting_user_id.present?
        participant_uids << requesting_user_id.to_s
      end
    end

    # Include requesting user id if provided and present
    if requesting_user_id.present?
      participant_uids << requesting_user_id.to_s
    end

    participant_uids.compact.map(&:to_s).reject(&:blank?).uniq
  rescue => e
    Rails.logger.error "❌ Error in GroupConversationService.resolve_participants: #{e.message}"
    []
  end
end
