# app/controllers/api/v1/learner_links_controller.rb
module Api::V1
  class LearnerLinksController < ApplicationController
    include Secured
    before_action :authorize

    # POST /api/v1/learner_links
    #
    # Creates a link between the currently authenticated user and a learner.
    # This is a secure endpoint that requires both the learner's unique
    # accession number and their school's ID to prevent ambiguity.
    def create
      # 1. Validate Parameters
      #    - Ensure both `accession_number` and `school_id` are present.
      if params[:accession_number].blank? || params[:school_id].blank?
        return render json: { error: 'accession_number and school_id are required' }, status: :unprocessable_entity
      end

      # 2. Securely Find the Learner
      #    - The learner is scoped by BOTH accession_number and school_id.
      #    - This is critical to prevent a user from accidentally (or maliciously)
      #      linking to a learner in a different school who happens to have the
      #      same accession number.
      @learner = Learner.find_by(
        accession_number: params[:accession_number],
        school_id: BSON::ObjectId.from_string(params[:school_id])
      )

      return render_learner_not_found unless @learner

      # 3. Get the Authenticated User's ID
      #    - The `authorize` before_action provides the `@decoded_token`.
      #    - We get the user's unique auth0_id from the token's 'sub' claim.
      current_user_auth0_id = @decoded_token.token['sub']

      # 4. Check for Existing Link
      #    - We check if the user's ID is already in the learner's parent array.
      #    - This prevents duplicate entries and unnecessary database writes.
      if @learner.parent_auth0_ids.include?(current_user_auth0_id)
        return render json: { message: 'Learner already linked' }, status: :ok
      end

      # 5. Create the Link (The Correct Way)
      #    - The link is created by adding the user's auth0_id to the learner's
      #      `parent_auth0_ids` array.
      #    - We use `add_to_set` to ensure uniqueness within the array.
      if @learner.add_to_set(parent_auth0_ids: current_user_auth0_id)
        render json: {
          message: 'Learner linked successfully',
          learner: @learner.to_api_hash
        }, status: :created
      else
        render json: {
          error: 'Failed to link learner',
          details: @learner.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    private

    def render_learner_not_found
      render json: { error: 'Learner not found with the provided accession_number and school_id' }, status: :not_found
    end
  end
end
