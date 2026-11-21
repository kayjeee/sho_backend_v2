module Api
  module V1
    class MyLearnersController < ApplicationController
      # GET /api/v1/parents/my_learners?auth0_id=xxx
      def index
        auth0_id = params[:auth0_id] || params[:user_auth0_id] || params[:auth0Id]

        if auth0_id.blank?
          return render json: { success: false, error: "Missing required parameter: auth0_id" }, status: :bad_request
        end

        parent_user = find_parent_user(auth0_id)
        unless parent_user
          return render json: { success: false, error: "User not found" }, status: :not_found
        end

        lookup_ids = [parent_user.id, parent_user.id.to_s, parent_user.auth0_id].compact.uniq

        learners = Learner.any_of(
          { :parent_ids.in => lookup_ids },
          { userAuth0Id: parent_user.auth0_id },
          { auth0Id: parent_user.auth0_id }
        ).to_a

        serialized_learners = learners.map { |l| serialize_learner(l) }

        render json: {
          success: true,
          total: serialized_learners.size,
          learners: serialized_learners,
          data: serialized_learners
        }, status: :ok
      rescue => e
        render_exception("MyLearnersController#index", e)
      end

      # GET /api/v1/parents/profile?auth0_id=xxx
      def profile
        auth0_id = params[:auth0_id] || params[:user_auth0_id] || params[:auth0Id]

        if auth0_id.blank?
          return render json: { success: false, error: "Missing required parameter: auth0_id" }, status: :bad_request
        end

        parent_user = find_parent_user(auth0_id)
        unless parent_user
          return render json: { success: false, error: "User not found" }, status: :not_found
        end

        render json: {
          success: true,
          data: parent_user.to_api_hash,
          user: parent_user.to_api_hash
        }, status: :ok
      rescue => e
        render_exception("MyLearnersController#profile", e)
      end

      private

      def find_parent_user(identifier)
        return nil if identifier.blank?
        ident_str = identifier.to_s.strip

        u = User.where(auth0_id: ident_str).first
        return u if u

        if BSON::ObjectId.legal?(ident_str)
          u = User.where(_id: BSON::ObjectId.from_string(ident_str)).first
          return u if u
        end

        nil
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
        nil
      end

      def serialize_learner(learner)
        g_id = (learner.try(:gradeId) || learner.try(:grade_id))&.to_s
        s_id = (learner.try(:schoolId) || learner.try(:school_id))&.to_s
        g_name = learner.try(:grade_name) || learner.grade&.name
        s_name = learner.try(:school_name) || learner.school&.schoolName || learner.school&.name

        {
          id: learner.id.to_s,
          _id: learner.id.to_s,
          first_name: learner.try(:first_name) || learner.try(:firstName),
          firstName: learner.try(:first_name) || learner.try(:firstName),
          last_name: learner.try(:last_name) || learner.try(:lastName),
          lastName: learner.try(:last_name) || learner.try(:lastName),
          full_name: learner.try(:full_name) || "#{learner.first_name} #{learner.last_name}".strip,
          accession_number: learner.try(:accession_number) || learner.try(:accessionNumber),
          accessionNumber: learner.try(:accession_number) || learner.try(:accessionNumber),
          school_id: s_id,
          schoolId: s_id,
          school_name: s_name,
          schoolName: s_name,
          grade_id: g_id,
          gradeId: g_id,
          grade_name: g_name,
          gradeName: g_name,
          gender: learner.gender,
          status: learner.status,
          phone: learner.phone,
          whatsapp: learner.whatsapp,
          parent_ids: Array(learner.parent_ids).map(&:to_s),
          created_at: learner.created_at&.iso8601,
          updated_at: learner.updated_at&.iso8601
        }
      end

      def render_exception(context, exception)
        cleaned_trace = BacktraceCleanerUtil.clean(exception.backtrace)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{cleaned_trace.first(5).join("\n")}"
        render json: { success: false, error: exception.message }, status: :internal_server_error
      end
    end
  end
end