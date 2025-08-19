module Api
  module V1
    class RequestAccessesController < ApplicationController
      before_action :set_request_access, only: %i[show approve reject]

      # Create a new request access
      def create
        school_id = params.dig(:request_access, :school_id)
        reason = params.dig(:request_access, :reason)
        logged_in_user_email = params.dig(:request_access, :logged_in_user_email)
        user_id = params.dig(:request_access, :user_id)

        # Validate required parameters
        if [ school_id, reason, logged_in_user_email, user_id ].any?(&:blank?)
          return render json: { error: "Missing required fields" }, status: :bad_request
        end

        school = School.find_by(id: school_id)
        user = User.find_by(id: user_id)

        unless school && user
          return render json: { error: "School or User not found" }, status: :not_found
        end

        if RequestAccess.exists?(school_id: school_id, user_id: user_id)
          return render json: { error: "Access request already exists" }, status: :conflict
        end

        new_access_request = RequestAccess.new(
          school_id: school_id,
          logged_in_user_email: logged_in_user_email,
          user_id: user_id,
          reason: reason,
          requested_at: Time.current,
          status: "Pending"
        )

        if new_access_request.save
          conversation = Conversation.find_or_create_by!(school_id: school_id, user_id: user_id)
          message = Message.create!(
            conversation_id: conversation.id,
            school_id: school_id,
            user_id: user_id,
            content: "User #{user.name} requested access to #{school.schoolName}. Reason: #{reason}"
          )

          render json: {
            message: "Access request submitted",
            data: new_access_request,
            conversation: conversation,
            extra_message: message
          }, status: :created
        else
          render json: { error: "Failed to create request", details: new_access_request.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Fetch all request accesses
      def index
        render json: RequestAccess.all, status: :ok
      end

      # Fetch a single request access
      def show
        render json: @request_access, status: :ok
      end

      # Fetch pending requests
      def pending_requests
        render json: RequestAccess.where(status: "Pending"), status: :ok
      end

      # Approve a request
      def approve
        accepted_by = params.dig(:request_access, :accepted_by)
        role = params.dig(:request_access, :role) # Role parameter (e.g., admin, teacher, etc.)

        return render json: { error: "Accepted by is required" }, status: :unprocessable_entity if accepted_by.blank?
        return render json: { error: "Role is required" }, status: :unprocessable_entity if role.blank?

        # Update request access status to approved
        if @request_access.update(status: "Approved", accepted_by: accepted_by)
          # Create the UserSchoolRole to assign the role to the user
          user_school_role = UserSchoolRole.create!(
            user_id: @request_access.user_id,
            school_id: @request_access.school_id,
            role: role
          )

          render json: {
            message: "Request approved and role assigned",
            data: @request_access,
            user_school_role: user_school_role
          }, status: :ok
        else
          render json: { error: "Approval failed", details: @request_access.errors.full_messages }, status: :unprocessable_entity
        end
      end


      # Reject a request
      def reject
        rejected_by = params.dig(:request_access, :rejected_by)
        return render json: { error: "Rejected by is required" }, status: :unprocessable_entity if rejected_by.blank?

        if @request_access.update(status: "Rejected", rejected_by: rejected_by)
          render json: { message: "Request rejected", data: @request_access }, status: :ok
        else
          render json: { error: "Rejection failed", details: @request_access.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # Fetch approved schools for a user
      def approved_schools
        email = params.dig(:user, :email)
        return render json: { error: "Email is required" }, status: :bad_request if email.blank?

        schools = School.where(id: RequestAccess.where(status: "Approved", logged_in_user_email: email).pluck(:school_id))
        render json: { message: "Approved schools retrieved", data: schools }, status: :ok
      end

      # Fetch requests by school and optional status
      def by_school
        school_id = params[:school_id]
        status = params[:status]

        requests = RequestAccess.where(school_id: school_id)
        requests = requests.where(status: status) if status.present?

        render json: { message: "Requests retrieved", data: requests }, status: :ok
      end

      private

      # Find request access by ID and ensure it's a valid BSON::ObjectId
      def set_request_access
        request_access_id = params.dig(:request_access, :request_access_id)

        if request_access_id.blank?
          return render json: { error: "Request access ID is required" }, status: :unprocessable_entity
        end

        begin
          @request_access = RequestAccess.find(BSON::ObjectId(request_access_id))
        rescue BSON::ObjectId::Invalid
          return render json: { error: "Invalid request access ID format" }, status: :unprocessable_entity
        end

        render json: { error: "Request access not found" }, status: :not_found unless @request_access
      end
    end
  end
end
