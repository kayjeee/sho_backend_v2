# frozen_string_literal: true

module Api
  module V1
    class LearnerInvitationsController < ApplicationController
      before_action :set_invitation, only: [:show, :update, :destroy, :accept, :decline, :cancel, :resend]

      # GET /api/v1/learner_invitations
      def index
        invitations = LearnerInvitation.all
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      rescue => e
        handle_exception(e, 'Failed to fetch invitations')
      end

      # GET /api/v1/learner_invitations/verify?token=...
      def verify
        token = params[:token]
        invitation = LearnerInvitation.where(token: token).first

        if invitation
          render_success(data: { invitation: invitation.to_api_hash })
        else
          render_error('Invitation not found', [], status: :not_found)
        end
      end

      # GET /api/v1/learner_invitations/:id
      def show
        render_success(data: { invitation: @invitation.to_api_hash })
      rescue => e
        handle_exception(e, 'Failed to fetch invitation')
      end

      # POST /api/v1/learner_invitations
      def create
        invitation = LearnerInvitation.new(invitation_params)
        invitation.sender_id = params[:sender_id] # Ideally current_user

        if invitation.save
          render_success(
            message: 'Learner invitation created successfully',
            data: { invitation: invitation.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to create invitation', invitation.errors.full_messages)
        end
      rescue => e
        handle_exception(e, 'Failed to create invitation')
      end

      # PATCH/PUT /api/v1/learner_invitations/:id
      def update
        if @invitation.update(invitation_params)
          render_success(
            message: 'Invitation updated successfully',
            data: { invitation: @invitation.reload.to_api_hash }
          )
        else
          render_error('Failed to update invitation', @invitation.errors.full_messages)
        end
      rescue => e
        handle_exception(e, 'Failed to update invitation')
      end

      # DELETE /api/v1/learner_invitations/:id
      def destroy
        @invitation.destroy
        render_success(message: 'Invitation removed successfully')
      rescue => e
        handle_exception(e, 'Failed to remove invitation')
      end

      # POST /api/v1/learner_invitations/:id/accept
      def accept
        result = UserServices::VerifyInvitationService.new(
          token: @invitation.token,
          auth0_id: params[:auth0_id]
        ).call

        if result[:success]
          render_success(message: 'Invitation accepted', data: { invitation: result[:invitation].to_api_hash })
        else
          render_error(result[:message])
        end
      rescue => e
        handle_exception(e, "Failed to accept invitation")
      end

      # POST /api/v1/learner_invitations/:id/decline
      def decline
        @invitation.update(status: 'declined')
        render_success(message: 'Invitation declined', data: { invitation: @invitation.to_api_hash })
      end

      # POST /api/v1/learner_invitations/:id/cancel
      def cancel
        @invitation.update(status: 'cancelled', cancelled_at: Time.current)
        render_success(message: 'Invitation cancelled', data: { invitation: @invitation.to_api_hash })
      end

      # POST /api/v1/learner_invitations/:id/resend
      def resend
        # Logic to resend invitation (e.g., trigger SMS/WhatsApp)
        @invitation.update(invited_at: Time.current)
        render_success(message: 'Invitation resent', data: { invitation: @invitation.to_api_hash })
      end

      # GET /api/v1/learner_invitations/pending
      def pending
        teacher_id = params[:teacher_id]
        school_id = params[:school_id]

        invitations = if teacher_id.present?
          LearnerInvitation.where(status: 'pending', sender_id: teacher_id)
        elsif school_id.present?
          LearnerInvitation.where(status: 'pending', school_id: school_id)
        else
          return render_error('A teacher_id or school_id is required to fetch pending invitations', [], status: :bad_request)
        end

        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      # GET /api/v1/learner_invitations/expired
      def expired
        invitations = LearnerInvitation.where(status: 'expired')
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      # GET /api/v1/learner_invitations/by_grade/:grade_id
      def by_grade
        invitations = LearnerInvitation.by_grade(params[:grade_id])
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      private

      def set_invitation
        @invitation = LearnerInvitation.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error('Invitation not found', [], status: :not_found)
      end

      def invitation_params
        params.require(:learner_invitation).permit(
          :recipient_phone_number, :parent_name, :school_id, :grade_id,
          :learner_number, :invited_via, :role, learner_numbers: [], learner_ids: []
        )
      end
    end
  end
end
