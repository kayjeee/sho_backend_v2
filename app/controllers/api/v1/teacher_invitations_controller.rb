# frozen_string_literal: true

module Api
  module V1
    class TeacherInvitationsController < ApplicationController
      before_action :set_invitation, only: [:show, :update, :destroy, :accept, :decline, :cancel, :resend]

      # GET /api/v1/teacher_invitations
      def index
        invitations = TeacherInvitation.all
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      rescue => e
        handle_exception(e, 'Failed to fetch invitations')
      end

      # GET /api/v1/teacher_invitations/verify?token=...
      def verify
        token = params[:token]
        invitation = TeacherInvitation.find_by_token(token)

        if invitation
          render_success(data: { invitation: invitation.to_api_hash })
        else
          render_error('Invitation not found', [], status: :not_found)
        end
      end

      # GET /api/v1/teacher_invitations/:id
      def show
        render_success(data: { invitation: @invitation.to_api_hash })
      rescue => e
        handle_exception(e, 'Failed to fetch invitation')
      end

      # POST /api/v1/teacher_invitations
      def create
        invitation = TeacherInvitation.new(invitation_params)
        invitation.sender_id = params[:sender_id] # Ideally current_user

        if invitation.save
          render_success(
            message: 'Teacher invitation created successfully',
            data: { invitation: invitation.to_api_hash },
            status: :created
          )
        else
          render_error('Failed to create invitation', invitation.errors.full_messages)
        end
      rescue => e
        handle_exception(e, 'Failed to create invitation')
      end

      # PATCH/PUT /api/v1/teacher_invitations/:id
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

      # DELETE /api/v1/teacher_invitations/:id
      def destroy
        @invitation.destroy
        render_success(message: 'Invitation removed successfully')
      rescue => e
        handle_exception(e, 'Failed to remove invitation')
      end

      # POST /api/v1/teacher_invitations/:id/accept
      def accept
        # Note: token might not be stored in plain text for TeacherInvitation,
        # but the set_invitation before_action has already found @invitation.
        # We need the raw token for VerifyInvitationService or we need to refactor
        # the service to accept the invitation object itself.
        # For now, we'll try to use @invitation.token if available.

        result = UserServices::VerifyInvitationService.new(
          token: params[:token] || @invitation.token,
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

      # POST /api/v1/teacher_invitations/:id/decline
      def decline
        @invitation.decline!
        render_success(message: 'Invitation declined', data: { invitation: @invitation.to_api_hash })
      end

      # POST /api/v1/teacher_invitations/:id/cancel
      def cancel
        @invitation.cancel!
        render_success(message: 'Invitation cancelled', data: { invitation: @invitation.to_api_hash })
      end

      # POST /api/v1/teacher_invitations/:id/resend
      def resend
        @invitation.update(invited_at: Time.current)
        render_success(message: 'Invitation resent', data: { invitation: @invitation.to_api_hash })
      end

      # GET /api/v1/teacher_invitations/pending
      def pending
        invitations = TeacherInvitation.pending
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      # GET /api/v1/teacher_invitations/expired
      def expired
        invitations = TeacherInvitation.expired
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      # GET /api/v1/teacher_invitations/by_school/:school_id
      def by_school
        invitations = TeacherInvitation.for_school(params[:school_id])
        render_success(data: { invitations: invitations.map(&:to_api_hash) })
      end

      private

      def set_invitation
        @invitation = TeacherInvitation.find(params[:id])
      rescue Mongoid::Errors::DocumentNotFound
        render_error('Invitation not found', [], status: :not_found)
      end

      def invitation_params
        params.require(:teacher_invitation).permit(
          :recipient_phone_number, :teacher_name, :school_id, :grade_id,
          :invited_via, :role, grade_ids: []
        )
      end
    end
  end
end
