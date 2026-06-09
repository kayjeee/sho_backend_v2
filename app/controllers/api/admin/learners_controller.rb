module Api
  module Admin
    class LearnersController < Api::Admin::BaseController
      # GET /api/admin/learners?gradeId=...
      def index
        grade_id_param = params[:gradeId] || params[:grade_id]

        if grade_id_param.blank?
          return render json: {
            success: false,
            error: "Bad Request",
            message: "Missing required gradeId parameter"
          }, status: :bad_request
        end

        # Enforce strict validation check on the ID
        unless BSON::ObjectId.legal?(grade_id_param)
          raise BSON::Error::InvalidObjectId
        end

        # Query matching learners
        @learners = Learner.where(grade_id: BSON::ObjectId.from_string(grade_id_param))

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
