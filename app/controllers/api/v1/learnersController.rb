# app/controllers/api/v1/learners_controller.rb
module Api
  module V1
    class LearnersController < Api::V1::BaseController
      # ------------------------------
      # GET /api/v1/learners/search
      # ------------------------------
      def search
        query_str = params[:q]
        school_id = params[:school_id] || params[:schoolId]

        if school_id.blank?
          return render json: { success: false, error: "School context identifier is required." }, status: :bad_request
        end

        if query_str.blank?
          return render json: { success: true, total: 0, learners: [] }, status: :ok
        end

        # Setup search criteria with multi-tenant filtering
        criteria = { "school_id" => school_id.to_s }

        # Safe case-insensitive regex search
        regex = /#{Regexp.escape(query_str)}/i
        criteria["$or"] = [
          { "firstName" => regex },
          { "lastName" => regex },
          { "first_name" => regex },
          { "last_name" => regex },
          { "accessionNumber" => regex },
          { "accession_number" => regex }
        ]

        # Run find operation directly on the collection to avoid relation mismatch bugs
        raw_docs = Learner.collection.find(criteria).limit(50)
        @learners = raw_docs.map { |doc| Learner.instantiate(doc) }

        render json: {
          success: true,
          total: @learners.size,
          learners: @learners.map { |learner|
            {
              id: learner.id.to_s,
              firstName: learner.try(:firstName) || learner.try(:first_name),
              lastName: learner.try(:lastName) || learner.try(:last_name),
              gender: learner.gender,
              accessionNumber: learner.try(:accessionNumber) || learner.try(:accession_number),
              gradeId: (learner.try(:gradeId) || learner.try(:grade_id))&.to_s,
              school_id: learner.school_id.to_s,
              parent_id: learner.try(:parent_id)&.to_s || nil,
              status: learner.try(:status) || "active"
            }
          }
        }, status: :ok
      end

      # ------------------------------
      # GET /api/v1/learners
      # ------------------------------
      def index
        learners = Learner.all
        learners = learners.where(school_id: params[:school_id]) if params[:school_id].present?
        learners = learners.where(grade_id: params[:grade_id]) if params[:grade_id].present?
        learners = learners.where(status: params[:status]) if params[:status].present?

        render json: {
          success: true,
          learners: learners.map { |l|
            {
              id: l.id.to_s,
              first_name: l.first_name,
              last_name: l.last_name,
              accession_number: l.accession_number,
              school_id: l.school_id
            }
          }
        }
      end

      # ------------------------------
      # GET /api/v1/learners/:id
      # ------------------------------
      def show
        learner = Learner.find(params[:id])
        render json: { success: true, learner: learner }
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Learner not found" }, status: :not_found
      end

      # ------------------------------
      # POST /api/v1/learners
      # ------------------------------
      def create
        learner = Learner.new(learner_params)
        if learner.save
          render json: { success: true, learner: learner }, status: :created
        else
          render json: { success: false, errors: learner.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # ------------------------------
      # PUT/PATCH /api/v1/learners/:id
      # ------------------------------
      def update
        learner = Learner.find(params[:id])
        if learner.update(learner_params)
          render json: { success: true, learner: learner }
        else
          render json: { success: false, errors: learner.errors.full_messages }, status: :unprocessable_entity
        end
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Learner not found" }, status: :not_found
      end

      # ------------------------------
      # DELETE /api/v1/learners/:id
      # ------------------------------
      def destroy
        learner = Learner.find(params[:id])
        learner.destroy
        render json: { success: true, message: "Learner deleted" }
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Learner not found" }, status: :not_found
      end

      # ------------------------------
      # PATCH actions
      # ------------------------------
      def graduate
        update_learner_status("graduated")
      end

      def activate
        update_learner_status("active")
      end

      def deactivate
        update_learner_status("inactive")
      end

      def transfer
        learner = Learner.find(params[:id])
        if learner.update(school_id: params[:new_school_id])
          render json: { success: true, learner: learner }
        else
          render json: { success: false, error: "Transfer failed" }, status: :unprocessable_entity
        end
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Learner not found" }, status: :not_found
      end

      def bulk_upload
        # Minimal bulk upload for now
        render json: { success: true, message: "Bulk upload received" }
      end

      private

      def update_learner_status(status)
        learner = Learner.find(params[:id])
        if learner.update(status: status)
          render json: { success: true, learner: learner }
        else
          render json: { success: false, error: "Status update failed" }, status: :unprocessable_entity
        end
      rescue Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Learner not found" }, status: :not_found
      end

      def learner_params
        params.require(:learner).permit(:first_name, :last_name, :accession_number, :school_id, :grade_id, :gender, :status)
      end
    end
  end
end
