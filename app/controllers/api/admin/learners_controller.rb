module Api
  module Admin
    class LearnersController < Api::Admin::BaseController
      # GET /api/admin/learners?gradeId=...&schoolId=...
      def index
        begin
          grade_param = params[:gradeId] || params[:grade_id]
          school_param = params[:schoolId] || params[:school_id]

          if grade_param.blank? && school_param.blank?
            return render json: {
              success: false,
              error: "Bad Request",
              message: "Missing required identifier (gradeId or schoolId)"
            }, status: :bad_request
          end

          # 1. Resolve school context if provided
          resolved_school_id = resolve_school_id(school_param) if school_param.present?

          # 2. Query execution with high-fidelity raw filters
          raw_filter = {}
          if grade_param.present?
            raw_filter["gradeId"] = grade_param
          elsif resolved_school_id
            raw_filter["school_id"] = resolved_school_id
          end

          raw_docs = Learner.collection.find(raw_filter)
          @learners = raw_docs.map { |doc| Learner.instantiate(doc) }

          render json: {
            success: true,
            total: @learners.size,
            learners: @learners.map { |l| serialize_learner_with_parents(l) }
          }
        rescue => e
          render json: {
            success: false,
            error: "An error occurred during query execution",
            message: e.message
          }, status: :internal_server_error
        end
      end

      private

      # Resolves a school param that may be a slug, name, or already an ObjectId.
      # Returns the school's actual _id string so it matches what learners store.
      def resolve_school_id(param)
        return param if param.blank?

        # Already a 24-char hex ObjectId — use directly
        return param if param.to_s.match?(/\A[0-9a-f]{24}\z/i)

        # Convert slug back to a name-like search
        # e.g. "far-north-secondary-school" → /far north secondary school/i
        name_pattern = Regexp.new(Regexp.escape(param.to_s.gsub('-', ' ')), Regexp::IGNORECASE)

        school_doc = School.collection.find(
          "$or" => [
            { "schoolName"   => name_pattern },
            { "school_name"  => name_pattern },
            { "name"         => name_pattern }
          ]
        ).first

        if school_doc
          school_doc["_id"].to_s
        else
          Rails.logger.warn "⚠️ resolve_school_id: no school found for param '#{param}'"
          param  # fall through — will return empty results rather than crash
        end
      end

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
