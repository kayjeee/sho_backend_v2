module Api
  module Admin
    class LearnersController < Api::Admin::BaseController
      # GET /api/admin/learners?gradeId=...&schoolId=...
      def index
        grade_id_param = params[:gradeId] || params[:grade_id]
        school_id_param = params[:schoolId] || params[:school_id]

        if grade_id_param.blank? && school_id_param.blank?
          return render json: {
            success: false,
            error: "Bad Request",
            message: "Missing required identifier (gradeId or schoolId)"
          }, status: :bad_request
        end

        # 1. Resolve school context if provided
        @school = find_school_by_id_or_slug(school_id_param) if school_id_param.present?

        # 2. Query execution with identifier resolution
        if grade_id_param.present?
          # Fetch matching both String and BSON variants for the grade
          query_criteria = [
            { gradeId: grade_id_param.to_s },
            { grade_id: grade_id_param.to_s }
          ]
          if BSON::ObjectId.legal?(grade_id_param)
            bson_id = BSON::ObjectId.from_string(grade_id_param)
            query_criteria << { gradeId: bson_id }
            query_criteria << { grade_id: bson_id }
          end
          @learners = Learner.any_of(*query_criteria)
        elsif @school
          # Collect all grade IDs for the school to catch learners missing a direct school link
          grade_ids_bson = @school.grades.pluck(:id)
          grade_ids_str  = grade_ids_bson.map(&:to_s)

          @learners = Learner.any_of(
            { :gradeId.in => grade_ids_str },
            { :grade_id.in => grade_ids_str },
            { :grade_id.in => grade_ids_bson },
            { schoolId: @school.id.to_s },
            { school_id: @school.id.to_s },
            { school_id: @school.id }
          )
        end

        render json: {
          success: true,
          total: @learners.count,
          learners: @learners.map { |l| serialize_learner_with_parents(l) }
        }
      end

      private

      def serialize_learner_with_parents(learner)
        parent_ids = learner.try(:parent_ids) || []

        parents_data = if parent_ids.any?
          # Hydrate parent user documents
          User.where(:id.in => parent_ids, roles: "parent").map do |p|
            {
              id: p.id.to_s,
              name: p.try(:name) || p.email.split('@').first.capitalize,
              email: p.email,
              phone: p.try(:phone_number) || p.try(:phone) || "No Contact"
            }
          end
        else
          []
        end

        {
          id: learner.id.to_s,
          name: "#{learner.first_name} #{learner.last_name}".presence || "Unnamed Learner",
          admission_number: learner.try(:accession_number) || "LNR-#{learner.id.to_s.last(4).upcase}",
          parents: parents_data
        }
      end
    end
  end
end
