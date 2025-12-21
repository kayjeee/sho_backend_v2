# app/controllers/api/v1/learner_links_controller.rb
module Api::V1
  class LearnerLinksController < ApplicationController
    include Secured
    before_action :authorize

    # POST /api/v1/learner_links
    # Creates a link between the currently authenticated user and a learner.
    def create
      if params[:accession_number].blank? || params[:school_id].blank?
        return render json: { error: 'accession_number and school_id are required' }, status: :unprocessable_entity
      end

      learner = Learner.find_by(
        accession_number: params[:accession_number],
        school_id: BSON::ObjectId.from_string(params[:school_id])
      )

      return render json: { error: 'Learner not found' }, status: :not_found unless learner

      current_user_auth0_id = @decoded_token.token['sub']

      # Check if the link already exists in the array.
      if learner.parent_auth0_ids.include?(current_user_auth0_id)
        return render json: { message: 'Learner already linked to your account' }, status: :ok
      end

      # Correct Logic: Add the user's ID to the `parent_auth0_ids` array.
      if learner.add_to_set(parent_auth0_ids: current_user_auth0_id)
        render json: { message: 'Learner linked successfully' }, status: :created
      else
        render json: { error: 'Failed to link learner', details: learner.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end
end
