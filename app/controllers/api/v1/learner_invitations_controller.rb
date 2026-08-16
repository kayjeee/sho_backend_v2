# app/controllers/api/v1/learner_invitations_controller.rb
module Api
  module V1
    class LearnerInvitationsController < ApplicationController
      before_action :set_invitation, only: [:show, :update, :destroy, :accept, :decline, :cancel, :resend]

      # GET /api/v1/learner_invitations
      def index
        begin
          invitations = LearnerInvitation.all
          invitations = invitations.where(school_id: params[:school_id]) if params[:school_id].present?

          render json: {
            success: true,
            learner_invitations: invitations.map { |inv| safe_invitation_hash(inv) }
          }, status: :ok
        rescue StandardError => e
          render_error(e.message)
        end
      end

      # GET /api/v1/learner_invitations/pending
      def pending
        begin
          invitations = LearnerInvitation.pending
          invitations = invitations.where(school_id: params[:school_id]) if params[:school_id].present?

          render json: {
            success: true,
            learner_invitations: invitations.map { |inv| safe_invitation_hash(inv) }
          }, status: :ok
        rescue StandardError => e
          render_error(e.message)
        end
      end

      # GET /api/v1/learner_invitations/expired
      def expired
        begin
          invitations = LearnerInvitation.expired
          invitations = invitations.where(school_id: params[:school_id]) if params[:school_id].present?

          render json: {
            success: true,
            learner_invitations: invitations.map { |inv| safe_invitation_hash(inv) }
          }, status: :ok
        rescue StandardError => e
          render_error(e.message)
        end
      end

      # GET /api/v1/learner_invitations/by_grade/:grade_id
      def by_grade
        begin
          invitations = LearnerInvitation.where(grade_id: params[:grade_id])

          render json: {
            success: true,
            learner_invitations: invitations.map { |inv| safe_invitation_hash(inv) }
          }, status: :ok
        rescue StandardError => e
          render_error(e.message)
        end
      end

      # GET /api/v1/learner_invitations/:id
      def show
        render json: {
          success: true,
          learner_invitation: safe_invitation_hash(@invitation)
        }, status: :ok
      end

      # POST /api/v1/learner_invitations/:id/accept
      def accept
        begin
          # Check if invitation was accepted using AcceptInvitationService or legacy model method
          auth0_id = params[:auth0_id] || params[:user_id]
          if auth0_id.present?
            result = UserServices::AcceptInvitationService.new(token: @invitation.token, auth0_id: auth0_id).call
            if result.success?
              render json: { success: true, message: "Invitation accepted successfully", invitation: safe_invitation_hash(@invitation.reload) }, status: :ok
            else
              render_error(result.errors.join(", "))
            end
          else
            # Revert to raw acceptance if no user is specified
            if @invitation.accept!
              render json: { success: true, message: "Invitation accepted", invitation: safe_invitation_hash(@invitation.reload) }, status: :ok
            else
              render_error("Failed to accept invitation")
            end
          end
        rescue StandardError => e
          render_error(e.message)
        end
      end

      # POST /api/v1/learner_invitations/:id/decline
      def decline
        if @invitation.decline!(params[:reason])
          render json: { success: true, message: "Invitation declined", invitation: safe_invitation_hash(@invitation.reload) }, status: :ok
        else
          render_error("Failed to decline invitation")
        end
      end

      # POST /api/v1/learner_invitations/:id/cancel
      def cancel
        if @invitation.cancel!(params[:reason])
          render json: { success: true, message: "Invitation cancelled", invitation: safe_invitation_hash(@invitation.reload) }, status: :ok
        else
          render_error("Failed to cancel invitation")
        end
      end

      # POST /api/v1/learner_invitations/:id/resend
      def resend
        # Reset invitation fields using the model's standard routine if supported
        begin
          @invitation.invited_at = Time.current
          @invitation.expires_at = 7.days.from_now
          @invitation.status = 0 # pending
          if @invitation.save
            render json: { success: true, message: "Invitation resent successfully", invitation: safe_invitation_hash(@invitation) }, status: :ok
          else
            render_error(@invitation.errors.full_messages.join(", "))
          end
        rescue StandardError => e
          render_error(e.message)
        end
      end

      private

      def set_invitation
        @invitation = LearnerInvitation.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound, BSON::Error::InvalidObjectId, Mongoid::Errors::InvalidFind
        render json: { success: false, message: "Invitation not found" }, status: :not_found
      end

      def safe_invitation_hash(invitation)
        begin
          invitation.to_api_hash
        rescue => e
          Rails.logger.error "❌ Error in safe_invitation_hash: #{e.message}"
          {
            id: invitation.id.to_s,
            token: invitation.respond_to?(:token) ? invitation.token : invitation.invitation_token,
            status: invitation.status,
            school_id: invitation.respond_to?(:school_id) ? invitation.school_id : nil
          }
        end
      end

      def render_error(msg)
        render json: { success: false, message: msg }, status: :unprocessable_entity
      end
    end
  end
end
