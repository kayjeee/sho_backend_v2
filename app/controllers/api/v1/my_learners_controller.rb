# app/controllers/api/v1/my_learners_controller.rb
module Api::V1
  class MyLearnersController < ApplicationController
    skip_before_action :authenticate_user!, raise: false

    before_action :set_user
    before_action :find_learners

    def index
      render json: { learners: @learners.map(&:to_api_hash), learner_count: @learners.count }, status: :ok
    end

    def profile
      render json: { parent: @user.to_api_hash, learner_count: @learners.count }, status: :ok
    end

    private

    def set_user
      # Handle URL encoding of pipe character
      decoded_auth0_id = CGI.unescape(params[:auth0_id].to_s)
      @user = User.find_by(auth0_id: decoded_auth0_id)
      
      unless @user
        Rails.logger.error "User not found: #{decoded_auth0_id}"
        render json: { error: 'Parent not found' }, status: :not_found
      end
    end

    def find_learners
      return unless @user

      Rails.logger.info "🔍 Finding learners for parent: #{@user.auth0_id}"
      
      # Convert school_ids to strings (User has ObjectIds, Learners have Strings)
      school_id_strings = @user.school_ids.map(&:to_s)
      Rails.logger.info "   Schools (as strings): #{school_id_strings}"
      
      # Use RAW MongoDB query with string school_ids
      query = {
        "parent_auth0_ids" => @user.auth0_id,
        "school_id" => { "$in" => school_id_strings },
        "$or" => [
          { "status" => "active" },  # String "active" (based on your data)
          { "status" => 0 }          # Integer 0 (for consistency)
        ]
      }
      
      Rails.logger.info "   Query: #{query.inspect}"
      
      # Execute direct MongoDB query
      start_time = Time.current
      learner_docs = Learner.collection.find(query).to_a
      end_time = Time.current
      
      Rails.logger.info "   Found #{learner_docs.count} documents in #{((end_time - start_time) * 1000).round(2)}ms"
      
      # Convert to Learner objects
      @learners = learner_docs.map do |doc|
        # Transform field names to match model
        attrs = transform_document_for_model(doc)
        Learner.new(attrs)
      end
      
      Rails.logger.info "✅ Returning #{@learners.count} learners"
    end

    # Transform MongoDB document to model attributes
    def transform_document_for_model(doc)
      attrs = {}
      
      doc.each do |key, value|
        case key.to_s
        when '_id'
          attrs['_id'] = value
        when 'firstName'
          attrs['first_name'] = value
        when 'lastName'
          attrs['last_name'] = value
        when 'accessionNumber'
          attrs['accession_number'] = value
        when 'gradeId'
          attrs['grade_id'] = value
        when 'school_id'
          # Keep as string (already string in database)
          attrs['school_id'] = value.to_s
        when 'auth0Id', 'userAuth0Id', 'status', 'gender', 'phone', 
             'tel_emergency', 'tel_home', 'whatsapp', 'telegram', 
             'date_of_birth', 'parent_info', 'parent_ids', 
             'parent_auth0_ids', 'enrollment_date', 'mobile_sync_id',
             'last_sync_at', 'created_at', 'updated_at'
          # Direct mapping
          attrs[key.to_s] = value
        when 'schoolName'
          # Skip - not in model
          next
        else
          Rails.logger.debug "   Skipping unexpected field: #{key}"
        end
      end
      
      attrs
    end
  end
end