module Api
  module V1
    class RequestAccessesController < ApplicationController
      before_action :set_request_access, only: [:show, :approve, :reject]

     # POST /api/v1/conversations
def create
  school_id = params.dig(:request_access, :school_id)
  reason = params.dig(:request_access, :reason)
  logged_in_user_email = params.dig(:request_access, :logged_in_user_email)
  user_id = params.dig(:request_access, :user_id)

  if school_id.blank? || reason.blank? || logged_in_user_email.blank? || user_id.blank?
    render json: { error: "Invalid request: school_id, reason, logged_in_user_email, and user_id are required" }, status: :bad_request
    return
  end

  school = School.find_by(id: school_id)
  user = User.find_by(id: user_id)

  if school.nil?
    render json: { error: "School not found" }, status: :not_found
    return
  end

  if user.nil?
    render json: { error: "User not found" }, status: :not_found
    return
  end

  if RequestAccess.exists?(school_id: school_id, user_id: user_id)
    render json: { error: "Access request already exists for this user in the school" }, status: :conflict
    return
  end

  # Create the access request
  new_access_request = RequestAccess.new(
    school_id: school_id,
    logged_in_user_email: logged_in_user_email,
    user_id: user_id,
    reason: reason,
    requested_at: Time.current,
    status: "Pending"
  )

  if new_access_request.save
    Rails.logger.info "Access request created: #{new_access_request.inspect}"

    # Ensure conversation exists
    conversation = Conversation.find_or_initialize_by(school_id: school_id, user_id: user_id)
    if conversation.new_record?
      conversation.save!
      Rails.logger.info "New conversation created: #{conversation.inspect}"
    end

    # Create a message in the conversation
    message = Message.create!(
      conversation_id: conversation.id,
      school_id: school_id,
      user_id: user_id,
      content: "User #{user.name} has requested access to the school: #{school.schoolName}. Reason: #{reason}"
    )
    Rails.logger.info "Message created: #{message.inspect}"

    render json: {
      message: "Access request submitted successfully",
      data: new_access_request.as_json,
      conversation: conversation.as_json,
      message: message.as_json
    }, status: :created
  else
    Rails.logger.error "Failed to create access request: #{new_access_request.errors.full_messages}"
    render json: { error: "Failed to create access request", details: new_access_request.errors.full_messages }, status: :unprocessable_entity
  end
end


      def index
        requests = RequestAccess.all
        render json: requests, status: :ok
      end

      def show
        render json: @request_access, status: :ok
      end

      def pending_requests
        pending = RequestAccess.where(status: 'pending')
        render json: pending, status: :ok
      end

      def approve
        accepted_by = params.dig(:request_access, :accepted_by)
        if accepted_by.blank?
          render json: { error: "Accepted by field is required" }, status: :unprocessable_entity
          return
        end

        if @request_access.update(status: 'approved', accepted_by: accepted_by)
          render json: { message: 'Request access approved successfully', data: @request_access }, status: :ok
        else
          render json: { error: "Failed to approve request access", details: @request_access.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def reject
        rejected_by = params.dig(:request_access, :rejected_by)
        if rejected_by.blank?
          render json: { error: "Rejected by field is required" }, status: :unprocessable_entity
          return
        end

        if @request_access.update(status: 'rejected', rejected_by: rejected_by)
          render json: { message: 'Access request rejected successfully.', data: @request_access }, status: :ok
        else
          render json: { error: 'Failed to reject access request.', details: @request_access.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def approved_schools
        logged_in_user_email = params.dig(:user, :email)
        if logged_in_user_email.blank?
          render json: { error: "Logged-in user email is required" }, status: :bad_request
          return
        end

        approved_requests = RequestAccess.where(status: 'approved', logged_in_user_email: logged_in_user_email)
        school_ids = approved_requests.pluck(:school_id)
        schools = School.where(id: school_ids)
        render json: { message: 'Approved schools retrieved successfully', data: schools }, status: :ok
      end
      def by_school
        school_id = params[:school_id]
        status = params[:status] # Capture status from query parameters
      
        # Convert school_id to BSON::ObjectId for accurate query matching
        school_id = BSON::ObjectId(school_id) rescue nil 
      
        requests = RequestAccess.where(school_id: school_id)
        requests = requests.where(status: status) if status.present?
      
        render json: { message: "Request accesses retrieved successfully", data: requests }
      end
      
      
      private

      def set_request_access
        @request_access = RequestAccess.find_by(id: params[:id])
        render json: { error: "Request access not found" }, status: :not_found unless @request_access
      end
    end
  end
end