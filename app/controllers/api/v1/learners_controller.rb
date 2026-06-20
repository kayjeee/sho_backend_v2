module Api
  module V1
    class LearnersController < Api::V1::BaseController
      before_action :set_learner, only: [:show, :update, :destroy, :graduate, :transfer, :activate, :deactivate]
      before_action :set_grade, only: [:index], if: -> { params[:grade_id].present? }
      before_action :set_request_context

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

        begin
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

        rescue StandardError => e
          # Catch any Mongoid lookup/formatting error and return as clean JSON
          # to avoid rendering development HTML web console templates.
          render json: {
            success: false,
            error: "An error occurred during query execution",
            message: e.message
          }, status: :internal_server_error
        end
      end

      # ------------------------------
      # GET /api/v1/learners
      # GET /api/v1/grades/:grade_id/learners
      # ------------------------------
      def index
        learners = @grade ? @grade.learners : Learner.all
        learners = learners.where(school_id: params[:school_id]) if params[:school_id].present?
        learners = learners.where(grade_id: params[:grade_id]) if params[:grade_id].present?
        learners = learners.where(status: params[:status]) if params[:status].present?

        page = (params[:page] || 1).to_i
        per_page = [(params[:per_page] || 20).to_i, 100].min
        total_count = learners.count
        learners = learners.skip((page - 1) * per_page).limit(per_page)

        render_success(
          data: learners.map { |l| learner_response(l) },
          pagination: {
            current_page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        )
      rescue => e
        render_exception("Learners#index", e)
      end

      # ------------------------------
      # GET /api/v1/learners/:id
      # ------------------------------
      def show
        render_success(data: learner_response(@learner))
      end

      # ------------------------------
      # POST /api/v1/learners
      # ------------------------------
      def create
        learner = Learner.new(learner_params)

        if learner.save
          mark_upload_learners_complete(params[:user_id])
          render_success(message: "Learner created", data: learner_response(learner), status: :created)
        else
          render_error(learner.errors.full_messages, :unprocessable_entity)
        end
      rescue => e
        render_exception("Learners#create", e)
      end

      # ------------------------------
      # PUT/PATCH /api/v1/learners/:id
      # ------------------------------
      def update
        if @learner.update(learner_params)
          mark_upload_learners_complete(params[:user_id])
          render_success(message: "Learner updated", data: learner_response(@learner))
        else
          render_error(@learner.errors.full_messages, :unprocessable_entity)
        end
      rescue => e
        render_exception("Learners#update", e)
      end

      # ------------------------------
      # DELETE /api/v1/learners/:id
      # ------------------------------
      def destroy
        if @learner.destroy
          render_success(message: "Learner deleted")
        else
          render_error(@learner.errors.full_messages, :unprocessable_entity)
        end
      end

      # ------------------------------
      # PATCH helpers
      # ------------------------------
      def graduate;  update_status(2, "graduated");  end
      def activate;  update_status(0, "activated");  end
      def deactivate; update_status(1, "deactivated"); end

      def transfer
        new_school_id = params[:new_school_id].presence
        return render_error("new_school_id is required", :bad_request) if new_school_id.blank?

        update_fields = { school_id: new_school_id }
        update_fields[:grade_id] = params[:new_grade_id] if params[:new_grade_id].present?

        if @learner.update(update_fields)
          mark_upload_learners_complete(params[:user_id])
          render_success(message: "Learner transferred", data: learner_response(@learner))
        else
          render_error(@learner.errors.full_messages, :unprocessable_entity)
        end
      rescue => e
        render_exception("Learners#transfer", e)
      end

      # ------------------------------
      # POST /api/v1/learners/bulk_upload
      # ------------------------------
      def bulk_upload
        learners_data = params[:data]
        return render_error("data must be an array", :bad_request) unless learners_data.is_a?(Array)

        successful, failed = [], []

        learners_data.each do |row|
          begin
            accession = row[:accessionNumber] || row["accessionNumber"]
            school_id = row[:school_id] || row["school_id"] || params[:school_id]
            raise ArgumentError, "accessionNumber and school_id are required" if accession.blank? || school_id.blank?

            learner_hash = {
              first_name: row[:firstName] || row["firstName"],
              last_name: row[:lastName] || row["lastName"],
              accession_number: accession,
              school_id: school_id,
              grade_id: row[:gradeId] || row["gradeId"],
              gender: map_gender(row[:gender] || row["gender"]),
              status: map_status(row[:status] || row["status"]) || 0,
              phone: row[:phone] || row["phone"],
              tel_emergency: row[:telEmergency] || row["telEmergency"],
              tel_home: row[:telHome] || row["telHome"],
              whatsapp: row[:whatsapp] || row["whatsapp"],
              telegram: row[:telegram] || row["telegram"]
            }.compact

            query = { accession_number: accession, school_id: school_id }
            result = Learner.collection.find_one_and_update(
              query,
              { "$set" => learner_hash },
              upsert: true,
              return_document: :after
            )

            successful << {
              id: result["_id"].to_s,
              name: "#{result["first_name"]} #{result["last_name"]}".strip,
              accession_number: result["accession_number"]
            }
          rescue => e
            failed << { row: row, errors: [e.message] }
          end
        end

        mark_upload_learners_complete(params[:user_id]) if successful.any?

        render_success(
          summary: { successful: successful.size, failed: failed.size },
          successful_imports: successful,
          failed_imports: failed
        )
      rescue => e
        render_exception("Learners#bulk_upload", e)
      end

      private

      # ------------------------------
      # Safely mark upload_learners step complete
      # ------------------------------
      def mark_upload_learners_complete(user_id)
        return unless user_id.present?

        user = User.find_by(id: user_id) || User.find_by(auth0_id: user_id)
        return unless user

        # Build onboarding_status if missing
        user.build_onboarding_status(completed_steps: [], skipped_steps: []) unless user.onboarding_status
        user.save! if user.changed?

        # Atomic MongoDB update for embedded document
        User.collection.find_one_and_update(
          { "_id" => user.id },
          {
            "$set" => {
              "onboarding_status.upload_learners" => true,
              "onboarding_status.completion_percentage" => calculate_completion_percentage(user),
              "onboarding_status.client_metadata.last_request" => {
                updated_at: Time.current.utc,
                step_completed: "upload_learners"
              }
            },
            "$addToSet" => { "onboarding_status.completed_steps" => "upload_learners" }
          }
        )
      rescue => e
        Rails.logger.warn "⚠️ Failed to mark upload_learners complete for #{user_id}: #{e.message}"
      end

      def calculate_completion_percentage(user)
        steps = %i[create_grades upload_learners send_invites]
        completed = steps.select { |s| user.onboarding_status[s] }
        ((completed.size.to_f / steps.size) * 100).to_i
      end

      # ------------------------------
      # Helpers
      # ------------------------------
      def set_learner
        @learner = Learner.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error("Learner not found", :not_found)
      end

      def set_grade
        @grade = Grade.find(params[:grade_id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error("Grade not found", :not_found)
      end

      def set_request_context
        @request_context = {
          request_id: request.uuid,
          user_agent: request.user_agent,
          ip_address: request.remote_ip,
          timestamp: Time.current.iso8601,
          endpoint: "#{request.method} #{request.path}"
        }
      end

      def learner_params
        params.require(:learner).permit(
          :first_name, :last_name, :accession_number,
          :school_id, :grade_id, :gender, :status,
          :phone, :tel_emergency, :tel_home, :whatsapp, :telegram
        )
      end

      def update_status(status_code, action)
        if @learner.update(status: status_code)
          mark_upload_learners_complete(params[:user_id])
          render_success(message: "Learner #{action}", data: learner_response(@learner))
        else
          render_error(@learner.errors.full_messages, :unprocessable_entity)
        end
      rescue => e
        render_exception("Learners##{action}", e)
      end

      def learner_response(l)
        {
          id: l.id.to_s,
          first_name: l.first_name,
          last_name: l.last_name,
          full_name: l.try(:full_name),
          accession_number: l.accession_number,
          status: l.status,
          phone: l.phone,
          school_id: l.school_id,
          grade_id: l.grade_id,
          created_at: l.created_at,
          updated_at: l.updated_at
        }
      end

      def map_gender(val)
        return 0 if val.blank?
        case val.to_s.strip.downcase
        when "male", "m", "0" then 0
        when "female", "f", "1" then 1
        else 2
        end
      end

      def map_status(val)
        return 0 if val.blank?
        case val.to_s.strip.downcase
        when "active", "0" then 0
        when "inactive", "1" then 1
        when "graduated", "2" then 2
        else 0
        end
      end

      # ------------------------------
      # Unified Response Helpers
      # ------------------------------
      def render_success(payload = {})
        status = payload.delete(:status) || :ok
        render json: { status: "success" }.merge(payload), status: status
      end

      def render_error(errors, status = :unprocessable_entity)
        render json: { status: "error", errors: Array(errors) }, status: status
      end

      def render_exception(context, exception)
        Rails.logger.error "❌ #{context} error: #{exception.message}\n#{exception.backtrace.first(5).join("\n")}"
        render json: { status: "error", error: exception.message }, status: :internal_server_error
      end
    end
  end
end
