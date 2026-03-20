# frozen_string_literal: true

module Api
  module V1
    module Public
      class InvitationsController < ApplicationController
        # POST /api/v1/public/invitations/learner/:token/accept
        def accept_learner_invitation
          token = params[:token]
          invitation = LearnerInvitation.where(token: token, status: 'pending').first

          if invitation
            invitation.update(status: 'accepted', accepted_at: Time.current)

            # If auth0_id is provided, link the user
            if params[:auth0_id].present?
              user = User.find_or_initialize_by(auth0_id: params[:auth0_id])
              user.email ||= invitation.recipient_phone_number + "@placeholder-parent.com"
              user.name  ||= invitation.parent_name
              user.roles |= ['parent']
              user.school_ids ||= []
              user.school_ids |= [invitation.school_id.to_s]
              user.save!

              # Link learners
              learners = if invitation.learner_ids.present?
                           Learner.where(:id.in => invitation.learner_ids)
                         elsif invitation.learner_numbers.present?
                           Learner.where(school_id: invitation.school_id, :accession_number.in => invitation.learner_numbers)
                         else
                           Learner.where(school_id: invitation.school_id, accession_number: invitation.learner_number)
                         end

              learners.each { |l| l.add_parent(user.auth0_id) }

              UserSchoolRole.find_or_create_by!(
                user: user,
                school_id: invitation.school_id,
                role: 'Parent',
                status: 0
              )
            end

            render_success(message: 'Invitation accepted', data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found or already accepted', [], status: :not_found)
          end
        end

        # POST /api/v1/public/invitations/teacher/:token/accept
        def accept_teacher_invitation
          token = params[:token]
          invitation = TeacherInvitation.find_by_token(token)

          if invitation && invitation.status == 'pending'
            invitation.accept!

            # If auth0_id is provided, link the user
            if params[:auth0_id].present?
              user = User.find_or_initialize_by(auth0_id: params[:auth0_id])
              user.email ||= invitation.recipient_phone_number + "@placeholder.com"
              user.name  ||= invitation.teacher_name
              user.roles |= ['teacher']
              user.school_ids ||= []
              user.school_ids |= [invitation.school_id.to_s]
              user.save!

              # Create teacher grade assignments
              grade_ids = invitation.grade_ids.presence || [invitation.grade_id].compact
              grade_ids.each do |gid|
                TeacherGradeAssignment.find_or_create_by!(
                  teacher: user,
                  grade_id: gid,
                  school_id: invitation.school_id,
                  role_type: 'primary',
                  assigned_by: invitation.sender || user,
                  status: 0
                )
              end

              UserSchoolRole.find_or_create_by!(
                user: user,
                school_id: invitation.school_id,
                role: 'Teacher',
                status: 0
              )
            end

            render_success(message: 'Invitation accepted', data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found or already accepted', [], status: :not_found)
          end
        end

        # GET /api/v1/public/invitations/learner/:token
        def show_learner_invitation
          token = params[:token]
          invitation = LearnerInvitation.where(token: token).first

          if invitation
            render_success(data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found', [], status: :not_found)
          end
        end

        # GET /api/v1/public/invitations/teacher/:token
        def show_teacher_invitation
          token = params[:token]
          invitation = TeacherInvitation.find_by_token(token)

          if invitation
            render_success(data: { invitation: invitation.to_api_hash })
          else
            render_error('Invitation not found', [], status: :not_found)
          end
        end
      end
    end
  end
end
